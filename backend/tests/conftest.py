import os, tempfile

os.environ["HUDDLE_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["HUDDLE_DRIVE_DIR"] = os.path.join(tempfile.mkdtemp(), "drive")
os.environ["HUDDLE_MOCK_PACE"] = "0"
# Tests stay offline. The running app refuses a build when these keys are missing.
os.environ["HUDDLE_OFFLINE"] = "1"
os.environ.pop("MODEL_API_KEY", None)
os.environ.pop("SERPAPI_API_KEY", None)
