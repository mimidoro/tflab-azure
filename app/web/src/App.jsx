import { useEffect, useState } from 'react';

// Injected at build time by the pipeline from the Terraform output "api_hostname".
// Locally: VITE_API_BASE_URL=http://localhost:5000 npm run dev
const API = import.meta.env.VITE_API_BASE_URL ?? '';

export default function App() {
  const [state, setState] = useState({ status: 'loading' });

  const load = async () => {
    setState({ status: 'loading' });
    try {
      const res = await fetch(`${API}/api/hello`);
      const body = await res.json();
      setState(res.ok ? { status: 'ok', body } : { status: 'error', body });
    } catch (err) {
      setState({ status: 'error', body: { detail: String(err) } });
    }
  };

  useEffect(() => { load(); }, []);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 560, margin: '4rem auto', padding: '0 16px' }}>
      <h1>Hello world</h1>
      <p>React (Static Web Apps) → .NET API (App Service) → Azure SQL</p>
      {state.status === 'loading' && <p>Calling API… (first call can take ~1 min while the free database resumes)</p>}
      {state.status === 'ok' && (
        <ul>
          <li><strong>API:</strong> {state.body.message}</li>
          <li><strong>Database:</strong> {state.body.db}</li>
        </ul>
      )}
      {state.status === 'error' && <p role="alert">Error: {state.body?.detail ?? 'unknown'}</p>}
      <button onClick={load}>Retry</button>
    </main>
  );
}
