"""
GreenOps Copilot — Unit tests for ADK tools.
Uses mocks so tests run without real GCP credentials.
"""

import asyncio
import os
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

# Stub env vars before importing modules
os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("ELECTRICITY_MAPS_API_KEY", "test-key")
os.environ.setdefault("GEMINI_API_KEY", "test-key")


class TestGetCarbonIntensity(unittest.IsolatedAsyncioTestCase):

    @patch("agent.tools.carbon_intensity.httpx.AsyncClient")
    async def test_returns_region_data(self, mock_client_cls):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "carbonIntensity": 34.2,
            "powerConsumptionBreakdown": {"wind": 800, "solar": 200, "gas": 100},
            "powerConsumptionTotal": 1100,
        }

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = AsyncMock(return_value=mock_response)
        mock_client_cls.return_value = mock_client

        from agent.tools.carbon_intensity import get_carbon_intensity
        with patch("agent.tools.carbon_intensity.asyncio.create_task"):
            result = await get_carbon_intensity(regions=["europe-west1"], forecast_hours=0)

        self.assertIn("regions", result)
        self.assertIn("europe-west1", result["regions"])
        region = result["regions"]["europe-west1"]
        self.assertEqual(region["current_gco2_kwh"], 34.2)
        self.assertIn("renewable_flag", region)

    @patch("agent.tools.carbon_intensity.httpx.AsyncClient")
    async def test_identifies_greenest_region(self, mock_client_cls):
        """The greenest_now field should point to the lowest-intensity region."""
        call_count = 0

        async def mock_get(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            mock_resp = MagicMock()
            mock_resp.raise_for_status = MagicMock()
            # Alternate intensities: europe-west1=30, us-central1=400
            intensity = 30.0 if call_count == 1 else 400.0
            mock_resp.json.return_value = {
                "carbonIntensity": intensity,
                "powerConsumptionBreakdown": {},
                "powerConsumptionTotal": 0,
            }
            return mock_resp

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = mock_get
        mock_client_cls.return_value = mock_client

        from agent.tools.carbon_intensity import get_carbon_intensity
        with patch("agent.tools.carbon_intensity.asyncio.create_task"):
            result = await get_carbon_intensity(
                regions=["europe-west1", "us-central1"], forecast_hours=0
            )

        self.assertEqual(result["greenest_now"], "europe-west1")


class TestScheduleWorkload(unittest.IsolatedAsyncioTestCase):

    async def test_rejects_past_run_at(self):
        from agent.tools.workload_scheduler import schedule_workload
        result = await schedule_workload(
            workload_description="Test job",
            target_region="europe-west1",
            run_at_utc="2020-01-01T00:00:00Z",
            current_gco2_kwh=400.0,
            target_gco2_kwh=30.0,
        )
        self.assertIn("error", result)
        self.assertIn("future", result["error"])

    async def test_rejects_unknown_region(self):
        from agent.tools.workload_scheduler import schedule_workload
        result = await schedule_workload(
            workload_description="Test job",
            target_region="mars-west1",
            run_at_utc="2030-01-01T14:00:00Z",
            current_gco2_kwh=400.0,
            target_gco2_kwh=30.0,
        )
        self.assertIn("error", result)

    async def test_calculates_co2_savings(self):
        from agent.tools.workload_scheduler import schedule_workload
        with patch("agent.tools.workload_scheduler._create_scheduler_entry") as mock_sched, \
             patch("agent.tools.workload_scheduler._log_scheduled_job"):
            mock_sched.return_value = {"scheduler_job_name": "test-job", "status": "created"}
            result = await schedule_workload(
                workload_description="Vectorise 50k documents",
                target_region="europe-west1",
                run_at_utc="2030-06-01T14:00:00Z",
                current_gco2_kwh=420.0,
                target_gco2_kwh=18.0,
            )

        self.assertIn("co2_saved_kg", result)
        self.assertIn("co2_reduction_pct", result)
        self.assertGreater(result["co2_saved_kg"], 0)
        self.assertGreater(result["co2_reduction_pct"], 90)  # 420 → 18 = ~96% reduction
        self.assertIn("confirmation", result)


class TestCarbonHistory(unittest.IsolatedAsyncioTestCase):

    @patch("agent.tools.supplementary_tools._bq")
    async def test_returns_summary(self, mock_bq_fn):
        mock_client = MagicMock()
        mock_bq_fn.return_value = mock_client

        mock_totals_row = MagicMock()
        mock_totals_row.total_jobs = 12
        mock_totals_row.total_co2_saved_kg = 84.3
        mock_totals_row.avg_reduction_pct = 78.4

        mock_client.query.return_value.result.return_value = [mock_totals_row]

        from agent.tools.supplementary_tools import query_carbon_history
        result = await query_carbon_history(days=7)

        self.assertIn("period_days", result)
        self.assertEqual(result["period_days"], 7)


class TestDashboardInsight(unittest.IsolatedAsyncioTestCase):

    async def test_includes_vision_context(self):
        from agent.tools.supplementary_tools import get_dashboard_insight
        result = await get_dashboard_insight(
            vision_description="the carbon chart with Belgium showing 30 gCO2/kWh",
        )
        self.assertIn("insights", result)
        self.assertIn("narration", result)
        self.assertTrue(any("I can see" in i for i in result["insights"]))

    async def test_identifies_high_carbon_anomaly(self):
        from agent.tools.supplementary_tools import get_dashboard_insight
        result = await get_dashboard_insight(
            vision_description="the dashboard",
            current_regions_data={
                "regions": {
                    "europe-west1": {"current_gco2_kwh": 30.0, "renewable_flag": True},
                    "us-central1": {"current_gco2_kwh": 450.0, "renewable_flag": False},
                },
                "greenest_now": "europe-west1",
                "greenest_window": None,
            },
        )
        self.assertTrue(any("450" in a or "high" in a for a in result["anomalies"]))


if __name__ == "__main__":
    unittest.main()
