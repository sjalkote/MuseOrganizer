import os, tempfile

os.environ["HUDDLE_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["HUDDLE_DRIVE_DIR"] = os.path.join(tempfile.mkdtemp(), "drive")
os.environ["HUDDLE_MOCK_PACE"] = "0"
