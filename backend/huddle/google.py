"""Google Drive, Sheets and Docs over plain REST, scope drive.file only (Huddle can touch only the files it creates).

Setup: docs/GOOGLE_WORKSPACE_SETUP.md. Needs the web OAuth client in GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET.
Docs: https://developers.google.com/drive/api/reference/rest/v3, /sheets/api/reference/rest, /docs/api/reference/rest.
"""
import os
import re
import urllib.parse

import httpx

CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID")
CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET")
REDIRECT_URI = os.environ.get("GOOGLE_REDIRECT_URI", "http://localhost:8000/auth/google/callback")
SCOPE = "https://www.googleapis.com/auth/drive.file"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
DRIVE = "https://www.googleapis.com/drive/v3/files"
MIME = {"folder": "application/vnd.google-apps.folder", "sheet": "application/vnd.google-apps.spreadsheet",
        "doc": "application/vnd.google-apps.document"}
STYLES = {"title": "TITLE", "heading": "HEADING_2"}


def configured():
    return bool(CLIENT_ID and CLIENT_SECRET)


def consent_url(state=""):
    return AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": CLIENT_ID, "redirect_uri": REDIRECT_URI, "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "consent", "state": state,
    })


def exchange(code, redirect_uri=REDIRECT_URI):
    """Trade an auth code for a refresh token. The iOS serverAuthCode uses an empty redirect_uri."""
    r = httpx.post(TOKEN_URL, data={"code": code, "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
                                    "redirect_uri": redirect_uri, "grant_type": "authorization_code"}, timeout=30)
    r.raise_for_status()
    token = r.json().get("refresh_token")
    if not token:
        raise ValueError("Google sent no refresh token. Remove Huddle at myaccount.google.com/permissions and sign in again.")
    return token


def _u16(text):
    return len(text.encode("utf-16-le")) // 2  # Docs indexes count UTF-16 code units


def doc_requests(blocks):
    """batchUpdate requests that write blocks ({type, text}) into an empty doc, styling titles, headings and bullets."""
    text, styled, i = "", [], 1
    for b in blocks:
        line = b["text"].replace("\n", " ") + "\n"
        styled.append((b["type"], i, i + _u16(line)))
        text += line
        i += _u16(line)
    reqs = [{"insertText": {"location": {"index": 1}, "text": text}}]
    for kind, start, end in styled:
        rng = {"startIndex": start, "endIndex": end}
        if kind in STYLES:
            reqs.append({"updateParagraphStyle": {"range": rng, "paragraphStyle": {"namedStyleType": STYLES[kind]},
                                                  "fields": "namedStyleType"}})
        elif kind == "bullet":
            reqs.append({"createParagraphBullets": {"range": rng, "bulletPreset": "BULLET_DISC_CIRCLE_SQUARE"}})
    return reqs


class Drive:
    def __init__(self, refresh_token):
        r = httpx.post(TOKEN_URL, data={"client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
                                        "refresh_token": refresh_token, "grant_type": "refresh_token"}, timeout=30)
        r.raise_for_status()
        self.http = httpx.Client(headers={"Authorization": f"Bearer {r.json()['access_token']}"}, timeout=60)

    def _call(self, method, url, **kw):
        r = self.http.request(method, url, **kw)
        r.raise_for_status()
        return r.json() if r.content else {}

    def _create(self, name, kind, parent=None):
        body = {"name": name, "mimeType": MIME[kind], **({"parents": [parent]} if parent else {})}
        return self._call("POST", DRIVE, json=body, params={"fields": "id,webViewLink"})

    def create_folder(self, name):
        return self._create(name, "folder")["id"]

    def create_sheet(self, folder, title, columns, rows, footer=None):
        f = self._create(title, "sheet", folder)
        values = [columns, *rows, *([[], [footer]] if footer else [])]
        base = f"https://sheets.googleapis.com/v4/spreadsheets/{f['id']}"
        self._call("PUT", f"{base}/values/A1", params={"valueInputOption": "USER_ENTERED"}, json={"values": values})
        self._call("POST", f"{base}:batchUpdate", json={"requests": [
            {"repeatCell": {"range": {"sheetId": 0, "endRowIndex": 1},
                            "cell": {"userEnteredFormat": {"textFormat": {"bold": True}}},
                            "fields": "userEnteredFormat.textFormat.bold"}},
            {"updateSheetProperties": {"properties": {"sheetId": 0, "gridProperties": {"frozenRowCount": 1}},
                                       "fields": "gridProperties.frozenRowCount"}},
            {"autoResizeDimensions": {"dimensions": {"sheetId": 0, "dimension": "COLUMNS"}}},
        ]})
        return f["webViewLink"]

    def create_doc(self, folder, title, blocks):
        f = self._create(title, "doc", folder)
        self._call("POST", f"https://docs.googleapis.com/v1/documents/{f['id']}:batchUpdate",
                   json={"requests": doc_requests(blocks)})
        return f["webViewLink"]

    @staticmethod
    def _sheet_id(url):
        m = re.search(r"/spreadsheets/d/([\w-]+)", url)
        if not m:
            raise ValueError(f"not a Google Sheets link: {url}")
        return m.group(1)

    def read_sheet(self, url):
        """(columns, rows) of the first tab, stopping at the blank row before the footer."""
        base = f"https://sheets.googleapis.com/v4/spreadsheets/{self._sheet_id(url)}"
        values = self._call("GET", f"{base}/values/A1:Z500").get("values", [])
        rows = []
        for r in values[1:]:
            if not any(r):
                break
            rows.append(r)
        return (values[0] if values else []), rows

    def update_sheet(self, url, columns, rows, footer=None):
        base = f"https://sheets.googleapis.com/v4/spreadsheets/{self._sheet_id(url)}"
        self._call("POST", f"{base}/values/A1:Z500:clear")
        values = [columns, *rows, *([[], [footer]] if footer else [])]
        self._call("PUT", f"{base}/values/A1", params={"valueInputOption": "USER_ENTERED"}, json={"values": values})

    def share(self, folder):
        self._call("POST", f"{DRIVE}/{folder}/permissions", json={"type": "anyone", "role": "reader"})
        return f"https://drive.google.com/drive/folders/{folder}"

    def delete(self, folder):
        self._call("DELETE", f"{DRIVE}/{folder}")
