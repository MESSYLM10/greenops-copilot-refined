import { useState, useEffect, useRef, useCallback } from "react";
import CarbonChart from "./components/CarbonChart";
import RegionCards from "./components/RegionCards";
import JobQueue from "./components/JobQueue";
import SavingsCounter from "./components/SavingsCounter";
import VoiceControl from "./components/VoiceControl";
import StatusBar from "./components/StatusBar";
import { useLiveSession } from "./hooks/useLiveSession";
import { useCarbonData } from "./hooks/useCarbonData";

const ORCHESTRATOR_URL = process.env.REACT_APP_ORCHESTRATOR_URL || "http://localhost:8080";

export default function App() {
  const [sessionId, setSessionId] = useState(null);
  const [scheduledJobs, setScheduledJobs] = useState([]);

  const { carbonData, isLoading, lastUpdated, refresh } = useCarbonData(ORCHESTRATOR_URL);

  const { isConnected, isListening, agentState, startSession, stopSession, toggleMic } =
    useLiveSession({
      orchestratorUrl: ORCHESTRATOR_URL,
      sessionId,
      onSessionId: setSessionId,
      onJobScheduled: (job) => setScheduledJobs((prev) => [job, ...prev].slice(0, 20)),
    });

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-left">
          <span className="logo-mark">⬡</span>
          <span className="logo-text">GreenOps Copilot</span>
        </div>
        <StatusBar
          isConnected={isConnected}
          agentState={agentState}
          lastUpdated={lastUpdated}
          onRefresh={refresh}
        />
      </header>

      <main className="app-body">
        <div className="left-panel">
          <SavingsCounter orchestratorUrl={ORCHESTRATOR_URL} />
          <CarbonChart data={carbonData} isLoading={isLoading} />
          <RegionCards
            data={carbonData}
            isConnected={isConnected}
            onRegionClick={(region) => {
              // Sends spoken prompt about the selected region
              toggleMic();
            }}
          />
        </div>

        <div className="right-panel">
          <VoiceControl
            isConnected={isConnected}
            isListening={isListening}
            agentState={agentState}
            onStart={startSession}
            onStop={stopSession}
            onToggleMic={toggleMic}
          />
          <JobQueue jobs={scheduledJobs} />
        </div>
      </main>

      <style>{`
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #0f1117; color: #e8eaf0; font-family: 'Inter', sans-serif; }

        .app { display: flex; flex-direction: column; min-height: 100vh; }

        .app-header {
          display: flex; align-items: center; justify-content: space-between;
          padding: 14px 24px;
          background: #161b27;
          border-bottom: 1px solid #1d9e7544;
        }
        .header-left { display: flex; align-items: center; gap: 10px; }
        .logo-mark { font-size: 22px; color: #1d9e75; }
        .logo-text { font-size: 16px; font-weight: 600; color: #e8eaf0; letter-spacing: 0.02em; }

        .app-body {
          display: grid;
          grid-template-columns: 1fr 340px;
          gap: 20px;
          padding: 20px 24px;
          flex: 1;
        }

        .left-panel { display: flex; flex-direction: column; gap: 16px; }
        .right-panel { display: flex; flex-direction: column; gap: 16px; }

        @media (max-width: 900px) {
          .app-body { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  );
}
