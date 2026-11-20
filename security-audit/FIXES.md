# Fixes Applied

Three fixes, all root-cause and minimal. No schema change, no new dependency. FIX-001/002 change only server behaviour; FIX-003 also touches the rider and vendor clients (a deliberate, approved contract change — see `VULNERABILITY-REPORT.md` VULN-002).

---

## FIX-001 — Rider onboarding cannot rewrite a foreign account (VULN-001)

**File:** `workers/api/src/app/services/vendor_service.py:1204` (`create_rider`)

```diff
             existing = (await self._conn.execute(
-                "SELECT id, phone, name, role FROM users WHERE phone = ?",
+                "SELECT id, phone, name, role, assigned_vendor_id FROM users WHERE phone = ?",
                 (phone_n,),
             )).fetchone()
             if existing is not None:
+                # Onboarding must never rewrite an existing account's role or
+                # owner: that let a vendor turn any customer/admin phone into
+                # their rider and then sign in as it (phone-only rider login).
+                if str(existing["role"]) != "rider":
+                    raise ConflictError(
+                        "This number already belongs to another account.",
+                        {"phone": phone_n},
+                    )
+                if str(existing["assigned_vendor_id"] or "") != str(vendor_id):
+                    raise ConflictError(
+                        "This rider belongs to another vendor.",
+                        {"phone": phone_n},
+                    )
                 rider_id = existing["id"]
                 await self._conn.execute(
-                    "UPDATE users SET name = ?, role = 'rider', assigned_vendor_id = ?, suspended = 0 WHERE id = ?",
-                    (name.strip(), vendor_id, rider_id),
+                    "UPDATE users SET name = ?, suspended = 0 WHERE id = ?",
+                    (name.strip(), rider_id),
                 )
```

**Why this is safe:** new phones still become riders under the caller; a vendor can still rename/reinstate their own riders. Only the three illegitimate transitions (customer → rider, admin → rider, other vendor's rider → mine) are refused, with `409 STATE_CONFLICT` and no hidden oracle (the message does not say which role the account has).

**Retest:** `harness3.py` → VENDOR-01 `409` (role stays `user`), VENDOR-02 `401`, VENDOR-05 `409` (admin stays `admin`), VENDOR-06 `409`. `tests/test_vendor_rider_onboarding.py` 5/5 pass.

---

## FIX-002 — Same-origin gate for cookie-authenticated writes (VULN-003)

**File:** `workers/api/src/app/api/auth_deps.py:73-118`, called at `get_current_user` (`:131`)

```diff
+_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
+
+def _same_origin(request: Request) -> bool:
+    candidate = (request.headers.get("origin") or "").strip()
+    if not candidate:
+        referer = (request.headers.get("referer") or "").strip()
+        if referer:
+            parts = referer.split("/")
+            candidate = "/".join(parts[:3]) if len(parts) >= 3 else ""
+    if not candidate or candidate == "null":
+        return False
+    host = (request.headers.get("host") or "").strip().lower()
+    if not host:
+        return False
+    scheme, _, netloc = candidate.partition("://")
+    netloc = netloc.split("/", 1)[0].lower()
+    return bool(netloc) and netloc == host and scheme in ("http", "https")
+
+def _reject_cross_site_cookie_write(request: Request) -> None:
+    auth = (request.headers.get("Authorization") or "").strip()
+    if auth:
+        return
+    if not request.cookies.get("sh_session"):
+        return
+    if request.method.upper() in _SAFE_METHODS:
+        return
+    if _same_origin(request):
+        return
+    raise HTTPException(status_code=403, detail="Cross-origin request rejected.")

 async def get_current_user(request: Request, conn=Depends(get_db_conn)) -> dict:
+    _reject_cross_site_cookie_write(request)
     token = _bearer(request)
```

**Why this is safe:** any client sending `Authorization: Bearer …` short-circuits the gate — that is every shipped client (Flutter apps, admin BFF, vendor portal). Only a browser cookie write from another origin, or one with no `Origin`/`Referer` at all, is refused. Same-origin cookie writes still work, so a future first-party cookie UI needs no change.

**Retest:** foreign-origin cancel-override `403` with the order unchanged; same-origin `200`; Bearer from foreign origin `200`; cookie `GET /v1/auth/me` `200`. `tests/test_csrf_cookie_auth.py` 6/6 pass.

---

## FIX-003 — Rider login requires a vendor-issued code (VULN-002)

**Files:** `workers/api/src/app/services/vendor_service.py` (`create_rider`), `workers/api/src/app/services/auth_service.py:565` (`rider_login`), `workers/api/src/app/api/v1/auth.py` (`RiderLoginIn`), `apps/rider_app/lib/{core/api_client.dart,features/auth/login_screen.dart}`, `apps/vendor_app/lib/features/riders/riders_screen.dart`

```diff
 # vendor_service — one issuing path, used by onboarding and by rotation
+    async def _issue_rider_code(self, vendor_id: str, rider_id: str) -> dict:
+        code = f"{secrets.randbelow(900000) + 100000}"
+        expires_at = (now + timedelta(days=RIDER_CODE_TTL_DAYS)).isoformat()
+        repo = AccessCodeRepo(self._conn)
+        await repo.revoke_all(rider_id, "rider")   # exactly one live code
+        await repo.issue(code_id=uuid.uuid4().hex, user_id=rider_id,
+            code_hash=hashlib.sha256(code.encode()).hexdigest(),
+            masked_hint=f"••{code[-2:]}", expected_role="rider",
+            expires_at=expires_at, created_by=vendor_id)
+        return {"access_code": code, "access_code_expires_at": expires_at}

+    async def reissue_rider_code(self, vendor_id: str, rider_id: str) -> dict:
+        owned = SELECT id FROM users WHERE id=? AND role='rider' AND assigned_vendor_id=?
+        if owned is None: raise NotFoundError("Rider not found.", {"id": rider_id})
+        return {"id": rider_id, **await self._issue_rider_code(vendor_id, rider_id)}

 # auth_service.rider_login — code is now a factor (and reads the user through the repo)
+        user = await self._users.find_by_phone(phone_n)
+        if user is not None and (user.get("role") != "rider" or user.get("suspended")):
+            user = None
+        want = hash_token((code or "").strip())
+        if user is not None:
+            for cand in await AccessCodeRepo(self._conn).find_valid(user["id"]):
+                if (str(cand.get("expected_role") or "") == "rider"
+                        and hmac.compare_digest(str(cand["code_hash"]), want)):
+                    matched_id = str(cand["id"]); break
+        if user is None or matched_id is None:
+            raise UnauthError("Invalid credentials.", {})
+        await AccessCodeRepo(self._conn).touch_last_used(matched_id)
```

**Route:** `POST /v1/vendor/riders/{rider_id}/code` → `VendorService.reissue_rider_code` (vendor-scoped; a foreign or unknown rider id is `404`, a rider token is `403`).

**Why this is safe:** it reuses the vendor/admin code door (`access_codes`, hash-only, expiring, revocable, audited by `last_used_at`) instead of inventing a second credential store. The reset remains a vendor action (re-onboard), so no rider can self-issue a code. Rate limits are per phone and per device. All failure modes collapse into one generic 401, so the door is not an account oracle.

**Retest:** phone-only `400`; three guessed codes `401`; vendor-issued code `200` with route access `200`; rotation kills the old code (`401`) while the new one works (`200`); E2E rider leg (onboard → code → login → route → rotate → login → complete) 26/26; `tests/test_rider_login_code.py` 12/12; `flutter analyze` clean and `flutter test` 9/9 (rider) + 96/96 (vendor, incl. 2 widget tests for the rotate action).

---

## Not fixed (requires approval)

### BUG-003 — completed delivery impossible when a code was never minted

Extending `reissue_delivery_code` to `assigned` orders changes policy/UX; left as a recommendation.
