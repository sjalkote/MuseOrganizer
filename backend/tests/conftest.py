import os, tempfile

os.environ["HUDDLE_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")
