import React from 'react';
import { NavLink } from 'react-router-dom';
import { LayoutGrid, LineChart, Search, SlidersHorizontal, ShieldAlert } from 'lucide-react';

const Navbar: React.FC = () => {
  return (
    <nav className="terminal-navbar">
      <div className="nav-container">
        <NavLink to="/" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <LayoutGrid size={18} />
          <span>DASHBOARD</span>
        </NavLink>
        <NavLink to="/operational" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <ShieldAlert size={18} />
          <span>OPERATIONAL</span>
        </NavLink>
        <NavLink to="/analysis" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <LineChart size={18} />
          <span>ANALYSIS</span>
        </NavLink>
        <NavLink to="/catalog" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <Search size={18} />
          <span>CATALOG</span>
        </NavLink>
        <NavLink to="/admin/settings" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <SlidersHorizontal size={18} />
          <span>ADMIN</span>
        </NavLink>
      </div>
    </nav>
  );
};

export default Navbar;
