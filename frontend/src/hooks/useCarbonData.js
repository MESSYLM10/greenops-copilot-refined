/**
 * useCarbonData
 * Polls /api/carbon/current every 60 seconds.
 * Returns structured data for the chart and region cards.
 */

import { useState, useEffect, useCallback } from "react";

const POLL_INTERVAL_MS = 60_000;

export function useCarbonData(orchestratorUrl) {
  const [carbonData, setCarbonData] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState(null);

  const fetch_data = useCallback(async () => {
    try {
      const res = await fetch(`${orchestratorUrl}/api/carbon/current`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      setCarbonData(transformCarbonData(json));
      setLastUpdated(new Date());
    } catch (e) {
      console.warn("Carbon data fetch failed:", e);
    } finally {
      setIsLoading(false);
    }
  }, [orchestratorUrl]);

  useEffect(() => {
    fetch_data();
    const interval = setInterval(fetch_data, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [fetch_data]);

  return { carbonData, isLoading, lastUpdated, refresh: fetch_data };
}

/**
 * Transform raw API response into chart-ready format.
 */
function transformCarbonData(raw) {
  if (!raw?.regions) return null;

  const regions = Object.entries(raw.regions)
    .filter(([, d]) => !d.error && d.current_gco2_kwh != null)
    .map(([region, data]) => ({
      region,
      label: REGION_LABELS[region] || region,
      current_gco2_kwh: data.current_gco2_kwh,
      renewable_pct: data.renewable_pct,
      renewable_flag: data.renewable_flag,
      forecast: data.forecast || [],
      best_window: data.best_window,
    }))
    .sort((a, b) => a.current_gco2_kwh - b.current_gco2_kwh);

  return {
    regions,
    greenest_now: raw.greenest_now,
    greenest_window: raw.greenest_window,
    retrieved_at: raw.retrieved_at,
    // Chart.js dataset format
    chart: {
      labels: regions.map((r) => r.label),
      datasets: [
        {
          label: "Current gCO₂/kWh",
          data: regions.map((r) => r.current_gco2_kwh),
          backgroundColor: regions.map((r) =>
            r.renewable_flag ? "rgba(29,158,117,0.75)" : "rgba(230,81,0,0.65)"
          ),
          borderColor: regions.map((r) =>
            r.renewable_flag ? "#1d9e75" : "#e65100"
          ),
          borderWidth: 1,
          borderRadius: 4,
        },
      ],
    },
  };
}

const REGION_LABELS = {
  "europe-west1":  "Belgium",
  "europe-north1": "Finland",
  "europe-west4":  "Netherlands",
  "us-west1":      "Oregon",
  "us-central1":   "Iowa",
  "asia-east1":    "Taiwan",
};
