# Delta Exchange Bot Architecture Diagrams (Canonical `backend/` Runtime)

This document maps how the current Rails runtime works end-to-end and how each major component behaves internally.

> Canonical runtime: `backend/` Rails app (`Trading::Runner`, JSON API, **Solid Queue** jobs, Postgres, Redis + `Rails.cache`, Delta REST/WebSocket, optional Telegram).

## 1) High-level system architecture (all components + interactions)

```mermaid
flowchart LR
    subgraph UI[Operator & UI]
      FE[Frontend/Vite Dashboard]
      OPS[Ops/SRE]
    end

    subgraph API[Rails API + Jobs]
      AC[ApplicationController\nAPI token auth]
      TSC[Api::TradingSessionsController]
      SQ[Solid Queue / ActiveJob]
      DTJ[DeltaTradingJob]
    end

    subgraph Runtime[Trading Runtime Process]
      RUN[Trading::Runner]
      BUS[Trading::EventBus]
      WS[Trading::MarketData::WsClient]
      STRAT[Bot::Strategy::MultiTimeframe]
      EXEC[Trading::ExecutionEngine]
      RISK[Trading::Risk::*]
      FILL[Trading::FillProcessor]
      OUPD[Trading::OrderUpdater]
      HND[Trading::Handlers::*]
    end

    subgraph Data[State & Persistence]
      PG[(Postgres)]
      REDIS[(Redis\nlocks + cache)]
      RC[Rails.cache]
    end

    subgraph Exchange[External]
      DELTA[Delta Exchange REST/WS]
      TG[Telegram]
    end

    FE -->|HTTP JSON| AC
    OPS -->|Start/Stop Session| TSC
    AC --> TSC
    TSC -->|perform_later(session_id)| SQ
    SQ --> DTJ
    DTJ -->|acquire delta_bot_lock:*| REDIS
    DTJ --> RUN

    RUN <--> BUS
    RUN --> STRAT
    RUN --> EXEC
    RUN --> WS
    WS <-->|public+private WS| DELTA
    EXEC <-->|orders REST| DELTA

    WS -->|tick/order/fill events| BUS
    BUS --> HND
    WS --> OUPD
    WS --> FILL

    EXEC --> RISK
    FILL --> RISK

    RUN --> PG
    EXEC --> PG
    FILL --> PG
    OUPD --> PG
    HND --> PG

    WS --> RC
    RUN --> RC
    RC --> REDIS

    RUN -->|startup/shutdown + signal notifications| TG
```

## 2) Session lifecycle and process control (API → job → runner)

```mermaid
sequenceDiagram
    autonumber
    participant User as Operator/UI
    participant API as Api::TradingSessionsController
    participant JobQ as Solid Queue
    participant Job as DeltaTradingJob
    participant Redis as Redis lock
    participant Runner as Trading::Runner

    User->>API: POST /api/trading_sessions
    API->>API: create TradingSession(status=running)
    API->>JobQ: DeltaTradingJob.perform_later(session_id)
    JobQ->>Job: perform(session_id)
    Job->>Redis: SET delta_bot_lock:<session_id> NX EX 86400
    alt lock acquired
      Job->>Runner: Runner.new(...).start
      Runner->>Runner: bootstrap!, register_event_handlers!, start_ws!, run_loop
    else lock already held
      Job-->>JobQ: abort duplicate runner
    end

    User->>API: DELETE /api/trading_sessions/:id
    API->>API: status=stopped, stopped_at=now
    API->>API: Trading::EmergencyShutdown.call (if creds present)
```

## 3) Runner internals (strategy pass + event-driven risk loop)

```mermaid
flowchart TD
    A[Runner.start] --> B[notify_startup_status]
    B --> C[bootstrap!]
    C --> C1[ensure_symbols_configured!]
    C1 --> C2[ProductCatalogSync.sync_all!]
    C -->|live mode| C3[Bootstrap::SyncPositions + SyncOrders]
    C -->|paper mode| C4[skip exchange bootstrap]

    C --> D[register_event_handlers!]
    D --> D1[order_filled -> Handlers::OrderHandler]
    D --> D2[position_updated -> Handlers::PositionHandler]
    D --> D3[tick_received -> TrailingStopHandler + SmcAlertTickSubscriber]

    D --> E[start_ws! thread]
    E --> F[run_loop every 5s]

    F --> G{strategy interval reached?}
    G -->|yes| H[run_strategy]
    H --> H1[MultiTimeframe.evaluate per symbol]
    H1 --> H2{signal?}
    H2 -->|yes| H3[persist signal + EventBus.publish(signal_generated)]
    H3 --> H4[ExecutionEngine.execute]
    H2 -->|no| H5[build_adaptive_signal from cache]
    H5 --> H4

    F --> I[NearLiquidationExit.check_all]
    F --> J[FundingMonitor.check_all]
    F --> K[sleep 5]
    K --> F
```

## 4) Market data/WebSocket ingestion internals

```mermaid
flowchart LR
    WSF[Bot::Feed::WebsocketFeed] -->|on_tick| TICK[handle_tick]
    WSF -->|on_message payload| Q[ingestion SizedQueue]

    subgraph Workers[WsClient worker threads]
      Q --> P[process_payload]
      P -->|v2/fills| PF[process_fill]
      P -->|v2/orders| PO[process_order]
      P -->|v2/orderbook| PB[on_orderbook_update]
    end

    TICK --> C1[Rails.cache write ltp:* + mark:*]
    TICK --> C2[Risk::Engine evaluate open positions]
    TICK --> C3[EventBus.publish tick_received]

    PF --> FP[FillProcessor.process]
    PO --> OU[OrderUpdater.process]

    PB --> OB[Orderbook::Book update]
    OB --> ADP[AdaptiveEngine.tick]
    ADP --> C4[cache adaptive:entry_context:*]
```

## 5) Execution/order/fill pipeline (signal to durable state)

```mermaid
sequenceDiagram
    autonumber
    participant Runner as Trading::Runner
    participant Engine as Trading::ExecutionEngine
    participant Guard as IdempotencyGuard (Redis)
    participant Risk as Trading::RiskManager + PortfolioGuard
    participant DB as Orders/Positions (Postgres)
    participant Delta as Delta REST
    participant WS as WsClient
    participant Fill as Trading::FillProcessor

    Runner->>Engine: execute(signal, session, client)
    Engine->>Guard: acquire(signal_key)
    Guard-->>Engine: true/false
    Engine->>Risk: validate!(signal) + portfolio guard
    Engine->>DB: find_or_create_position + create order row

    alt paper mode
      Engine->>Fill: simulate_fill_at_market -> FillProcessor.process
    else live mode
      Engine->>Delta: place_order(product_id, side, type, size, price)
      Delta-->>WS: v2/orders + v2/fills events
      WS->>Fill: process_fill(event)
    end

    Fill->>DB: insert fill idempotently + aggregate order + recalc position
    Fill->>DB: portfolio ledger + risk executor
```

## 6) Data ownership + flow map

```mermaid
flowchart TB
    subgraph Postgres
      TS[trading_sessions]
      POS[positions]
      ORD[orders]
      FIL[fills]
      TRD[trades]
      GS[generated_signals]
      SC[symbol_configs]
      SET[settings]
      PF[portfolios + ledger]
    end

    subgraph RedisAndCache
      LOCK[delta_bot_lock:*]
      IDEM[delta:order:* idempotency]
      LTP[ltp:* / mark:*]
      ADAPT[adaptive:entry_context:*]
      RUNTIME[runtime_config:*]
      ADASH[delta:analysis:dashboard]
      SMCAL[delta:smc_alert:*]
    end

    API[API controllers] --> TS
    API --> SET
    Runner[Trading::Runner] --> GS
    Runner --> SC
    Execution[ExecutionEngine] --> ORD
    Execution --> POS
    WsFill[FillProcessor/OrderUpdater] --> FIL
    WsFill --> ORD
    WsFill --> POS
    Handlers[Handlers::OrderHandler] --> TRD
    Risk[Risk + liquidation logic] --> PF

    DeltaWS[Delta WS ticks] --> LTP
    DeltaWS --> ADAPT
    Runner --> IDEM
    DeltaTradingJob --> LOCK
    RuntimeConfig[Trading::RuntimeConfig] --> RUNTIME
```

## 7) Notes for contributors

- Run exactly one long-lived runner per session (`delta_bot_lock:<session_id>` prevents duplicate job dispatch, but separate manually started processes can still collide).
- `Trading::EventBus` is in-process global state; `Runner#start` calls `EventBus.reset!` on shutdown.
- In paper mode, fills are generated locally by `ExecutionEngine#simulate_fill_at_market`; in live mode, fills/orders arrive from exchange WS streams and are reconciled by `FillProcessor`/`OrderUpdater`.
- Strategy pass cadence and WS ingestion throughput are runtime-tunable (`runner.strategy_interval_seconds`, `WS_INGESTION_WORKERS`, queue size, etc.).
- **SMC Telegram event alerts** (`SmcAlertTickSubscriber` on `tick_received`) run only inside the same OS process as `Trading::Runner`; the 15m **`AnalysisDashboardRefreshJob`** is independent and writes `delta:analysis:dashboard`. See [`smc_event_alerts.md`](smc_event_alerts.md).
