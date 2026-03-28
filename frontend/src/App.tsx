import React from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import DashboardPage from './pages/DashboardPage';
import CatalogPage from './pages/CatalogPage';

const App: React.FC = () => {
  return (
    <BrowserRouter>
      <div className="terminal-container">
        <Navbar />
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/catalog" element={<CatalogPage />} />
        </Routes>
      </div>
    </BrowserRouter>
  );
};

export default App;
