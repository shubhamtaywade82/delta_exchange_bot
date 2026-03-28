import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Search, Loader2, Plus, Trash2 } from 'lucide-react';

interface Product {
  symbol: string;
  description: string;
  contract_type: string;
}

interface SymbolConfig {
  id: number;
  symbol: string;
  enabled: boolean;
}

const CatalogPage: React.FC = () => {
  const [products, setProducts] = useState<Product[]>([]);
  const [watchlist, setWatchlist] = useState<SymbolConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

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
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const toggleWatch = async (symbol: string) => {
    const entry = watchlist.find(w => w.symbol === symbol);
    try {
      if (entry?.enabled) {
        await axios.delete(`/api/symbol_configs/${entry.id}`);
      } else {
        await axios.post('/api/symbol_configs', { symbol, leverage: 10, enabled: true });
      }
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  const filtered = products.filter(p => p.symbol.toLowerCase().includes(search.toLowerCase()));

  if (loading) return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Loader2 className="animate-spin text-primary" size={48} />
    </div>
  );

  return (
    <div className="catalog-page p-6">
      <header className="mb-8">
        <h2 className="text-2xl font-bold tracking-tighter mb-4 text-white uppercase italic">Product_Catalog</h2>
        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-white/40" size={16} />
          <input 
            className="w-full bg-white/5 border border-white/10 rounded px-10 py-2 outline-none text-white font-mono text-sm focus:border-primary transition-all" 
            placeholder="FILTER_CONTRACTS..." 
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </header>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 pb-20">
        {filtered.map(p => {
          const entry = watchlist.find(w => w.symbol === p.symbol);
          const isWatch = entry?.enabled;
          return (
            <div key={p.symbol} className={`p-4 border rounded-lg bg-black/40 transition-all ${isWatch ? 'border-primary shadow-[0_0_15px_rgba(var(--primary-rgb),0.1)]' : 'border-white/10'}`}>
              <div className="flex justify-between items-start">
                <div>
                  <div className="text-lg font-bold text-white tracking-tight">{p.symbol}</div>
                  <div className="text-xs text-white/40 uppercase font-mono mb-2">{p.contract_type}</div>
                  <div className="text-sm text-white/60 line-clamp-1">{p.description}</div>
                </div>
                <button 
                  className={`p-2 rounded-lg transition-colors ${isWatch ? 'text-red-400 bg-red-400/10' : 'text-primary bg-primary/10'}`}
                  onClick={() => toggleWatch(p.symbol)}
                >
                  {isWatch ? <Trash2 size={18} /> : <Plus size={18} />}
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default CatalogPage;
