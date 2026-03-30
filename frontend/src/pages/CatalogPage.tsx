import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Search, 
  Loader2
} from 'lucide-react';

interface Product {
  id: number;
  symbol: string;
  description: string;
  contract_type: string;
}

interface SymbolConfig {
  id: number;
  symbol: string;
  enabled: boolean;
  leverage: number;
  product_id?: number;
}

const CATEGORIES = ['ALL', 'BTC', 'ETH', 'USDT'];

const CatalogPage: React.FC = () => {
  const [products, setProducts] = useState<Product[]>([]);
  const [watchlist, setWatchlist] = useState<SymbolConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('ALL');
  const [leverages, setLeverages] = useState<Record<string, number>>({});

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const [resP, resW] = await Promise.all([
        axios.get('/api/products'),
        axios.get('/api/symbol_configs')
      ]);
      setProducts(resP.data);
      setWatchlist(resW.data);
      
      // Initialize leverage inputs from watchlist or default to 10
      const initialLevs: Record<string, number> = {};
      resP.data.forEach((p: Product) => {
        const entry = resW.data.find((w: SymbolConfig) => w.symbol === p.symbol);
        initialLevs[p.symbol] = entry?.leverage || 10;
      });
      setLeverages(initialLevs);
    } catch (err) {
      console.error("Catalog fetch error", err);
    } finally {
      setLoading(false);
    }
  };

  const handleLeverageChange = (symbol: string, val: string) => {
    const num = parseInt(val) || 1;
    setLeverages(prev => ({ ...prev, [symbol]: Math.max(1, Math.min(100, num)) }));
  };

  const toggleWatch = async (symbol: string) => {
    const entry = watchlist.find(w => w.symbol === symbol);
    const product = products.find(p => p.symbol === symbol);
    const targetLeverage = leverages[symbol] || 10;
    
    try {
      if (entry?.enabled) {
        await axios.delete(`/api/symbol_configs/${entry.id}`);
      } else {
        await axios.post('/api/symbol_configs', { 
          symbol, 
          leverage: targetLeverage, 
          enabled: true,
          product_id: product?.id
        });
      }
      fetchData();
    } catch (err) {
      console.error("Toggle symbol error", err);
    }
  };

  const filtered = products.filter(p => {
    const matchesSearch = p.symbol.toLowerCase().includes(search.toLowerCase());
    const matchesCat = category === 'ALL' || p.symbol.includes(category);
    return matchesSearch && matchesCat;
  });

  if (loading) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4">
      <Loader2 className="animate-spin text-primary" size={48} />
      <span className="font-mono text-sm tracking-widest text-primary/60">FETCHING_PRODUCT_LIST...</span>
    </div>
  );

  return (
    <div className="catalog-page">
      <header className="catalog-header">
        <div>
          <h2>PRODUCT_CATALOG</h2>
          <div className="system-status">
            <span className="dot online"></span>
            <span>{products.length} INSTRUMENTS_ONLINE</span>
            <span className="divider">|</span>
            <span className="pos">{watchlist.filter(w => w.enabled).length} ACTIVE_IN_WATCHLIST</span>
          </div>
        </div>
        
        <div className="catalog-controls">
          <div className="filter-group">
            {CATEGORIES.map(cat => (
              <button 
                key={cat} 
                className={`filter-btn ${category === cat ? 'active' : ''}`}
                onClick={() => setCategory(cat)}
              >
                {cat}
              </button>
            ))}
          </div>

          <div className="search-wrapper">
            <Search className="search-icon" size={16} />
            <input 
              className="search-input" 
              placeholder="FILTER_CONTRACTS..." 
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>
      </header>

      <div className="catalog-grid pb-20">
        {filtered.slice(0, 100).map(p => {
          const entry = watchlist.find(w => w.symbol === p.symbol);
          const isWatch = entry?.enabled;
          
          return (
            <div key={p.symbol} className={`terminal-section product-card ${isWatch ? 'active-glow' : ''}`}>
              <div className="product-info">
                <span className="sym">{p.symbol}</span>
                <span className="desc">{p.description}</span>
              </div>
              
              <div className="product-meta">
                <div className="meta-item">
                  <label>CONTRACT_TYPE</label>
                  <span className="font-mono text-xs">{p.contract_type}</span>
                </div>
                <div className="meta-item">
                  <label>STATUS</label>
                  <span className={isWatch ? 'pos' : 'text-muted'}>
                    {isWatch ? 'READY_FOR_EXEC' : 'IDLE'}
                  </span>
                </div>
              </div>

              <div className="card-actions">
                <div className="leverage-input-group">
                  <label>RISK_LEVERAGE</label>
                  <div className="flex items-center gap-2">
                    <input 
                      type="number"
                      value={leverages[p.symbol] || ''}
                      onChange={(e) => handleLeverageChange(p.symbol, e.target.value)}
                      disabled={isWatch}
                    />
                    <span className="text-xs text-muted">X</span>
                  </div>
                </div>

                <button 
                  className={isWatch ? 'btn-remove' : 'btn-add'}
                  onClick={() => toggleWatch(p.symbol)}
                >
                  {isWatch ? 'DISABLE' : 'ENABLE'}
                </button>
              </div>
            </div>
          );
        })}
      </div>
      
      {filtered.length > 100 && (
        <div className="text-center py-8 text-muted font-mono text-xs border-t border-glass">
          + {filtered.length - 100} MORE INSTRUMENTS HIDDEN. REFINING_SEARCH RECOMMENDED.
        </div>
      )}
    </div>
  );
};

export default CatalogPage;
