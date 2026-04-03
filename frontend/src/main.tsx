import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { LiveLtpProvider } from './liveLtp/LiveLtpProvider'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <LiveLtpProvider>
      <App />
    </LiveLtpProvider>
  </StrictMode>,
)
