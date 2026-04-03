import React from 'react';

const AppFooter: React.FC = () => {
  return (
    <footer className="terminal-footer">
      <div className="command-line">
        <span className="prompt">root@delta-bot:v2.0#</span>
        <span className="cursor-blink">Awaiting input_</span>
      </div>
      <div className="system-metrics">
        <span>MODE: DRY_RUN</span>
        <span>SESSIONS: ACTIVE</span>
        <span>LOAD: 0.24ms</span>
      </div>
    </footer>
  );
};

export default AppFooter;
