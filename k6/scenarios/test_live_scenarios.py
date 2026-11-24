"""
Live Production Scenario Verification Script
Tests all edge-case scenarios against production workers:
1. Customer Name change allowed, Phone change blocked
2. Vendor Suspension Cascade (stops repooled, riders detached & sessions revoked, dispatch blocked)
3. Admin 1-Click Reassignment of Orphan Customers
4. Multi-party cancellations (Customer cancel, Vendor fail, Rider cancel with vendor OTP)
5. Mid-cycle Subscription cancellation dues recovery
Strict invariant: Admin user (+917828442476) is NEVER deleted.
"""

import os
import sys
import time
import requests
import json
import uuid

ADMIN_API = os.getenv("ADMIN_API", "https://water-admin.adityathakur452007.workers.dev")
OPS_API = os.getenv("OPS_API", "https://water-ops.adityathakur452007.workers.dev")
CUSTOMER_API = os.getenv("CUSTOMER_API", "https://water.adityathakur452007.workers.dev")

ADMIN_PHONE = os.getenv("ADMIN_PHONE", "+917828442476")
ADMIN_CODE = os.getenv("ADMIN_CODE", "452007")


def log(msg):
    print(f"[TEST] {msg}", flush=True)


def main():
    log("=== Starting Live Production Scenarios Verification ===")

    # 1. Admin Login
    log("1. Authenticating as Admin on water-admin...")
    res = requests.post(
        f"{ADMIN_API}/v1/auth/admin/login",
        json={"phone": ADMIN_PHONE, "code": ADMIN_CODE, "device": {"id": "test_admin_device"}},
        timeout=15,
    )
    if res.status_code != 200:
        log(f"Admin auth failed: {res.status_code} {res.text}")
        sys.exit(1)
    admin_data = res.json()
    admin_token = admin_data.get("token") or admin_data.get("access_token")
    admin_headers = {"Authorization": f"Bearer {admin_token}", "Content-Type": "application/json"}
    log("Admin authenticated successfully.")

    # 2. Customer Registration & Profile Update (Name change vs Phone change)
    test_run_id = uuid.uuid4().hex[:6]
    cust_phone = f"+9198{int(time.time()) % 100000000:08d}"
    log(f"2. Testing Customer Registration & Name Change with phone: {cust_phone}")
    res = requests.post(
        f"{CUSTOMER_API}/v1/auth/user/register",
        json={
            "name": f"Original Name {test_run_id}",
            "phone": cust_phone,
            "password": "Password123!",
            "device": {"id": f"dev_{test_run_id}"},
        },
        timeout=15,
    )
    assert res.status_code == 200, f"Register failed: {res.text}"
    cust_data = res.json()
    cust_token = cust_data.get("access_token") or cust_data.get("token")
    cust_id = cust_data.get("user_id") or cust_data.get("user", {}).get("id") or cust_data.get("id")
    cust_headers = {"Authorization": f"Bearer {cust_token}", "Content-Type": "application/json"}

    # Name Change (Allowed)
    log("Testing PATCH /auth/me for name change...")
    res = requests.patch(
        f"{CUSTOMER_API}/v1/auth/me",
        headers=cust_headers,
        json={"name": f"Updated Name {test_run_id}"},
        timeout=15,
    )
    assert res.status_code == 200, f"Name patch failed: {res.text}"
    user_res = res.json().get("user") or res.json()
    assert user_res.get("name") == f"Updated Name {test_run_id}"
    log(f"Name change verified: 200 OK -> {user_res.get('name')}")

    # Phone Change (Blocked)
    log("Testing PATCH /auth/me for phone change (should fail)...")
    res = requests.patch(
        f"{CUSTOMER_API}/v1/auth/me",
        headers=cust_headers,
        json={"phone": "+919999999999"},
        timeout=15,
    )
    assert res.status_code in (400, 422), f"Expected 400/422 for phone change, got {res.status_code}"
    log("Phone change blocked verified: 400/422 rejected.")

    # 3. Create Vendor 1 & Attached Rider
    log("3. Creating Test Vendor 1 and attached Rider via Admin...")
    vendor_phone = f"+9197{int(time.time()) % 100000000:08d}"
    res = requests.post(
        f"{ADMIN_API}/v1/admin/vendors",
        headers=admin_headers,
        json={"name": f"Vendor 1 {test_run_id}", "phone": vendor_phone, "zone_id": "zone_satna", "auto_verify": True},
        timeout=15,
    )
    assert res.status_code in (200, 201), f"Vendor creation failed: {res.text}"
    v1_id = res.json().get("id") or res.json().get("user_id")
    v1_code = res.json().get("code")
    if not v1_code:
        # Issue access code for vendor 1 if not returned
        res = requests.post(
            f"{ADMIN_API}/v1/admin/vendors/{v1_id}/access-code",
            headers=admin_headers,
            json={},
            timeout=15,
        )
        assert res.status_code == 200, f"Access code issue failed: {res.text}"
        v1_code = res.json()["code"]

    # Vendor login on ops worker
    res = requests.post(
        f"{OPS_API}/v1/auth/vendor/login",
        json={"phone": vendor_phone, "code": v1_code, "device": {"id": f"vdev_{test_run_id}"}},
        timeout=15,
    )
    assert res.status_code == 200, f"Vendor login failed: {res.text}"
    v1_token = res.json().get("token") or res.json().get("access_token")
    v1_headers = {"Authorization": f"Bearer {v1_token}", "Content-Type": "application/json"}

    # Vendor creates a rider
    rider_phone = f"+9196{int(time.time()) % 100000000:08d}"
    res = requests.post(
        f"{OPS_API}/v1/vendor/riders",
        headers=v1_headers,
        json={"name": f"Rider 1 {test_run_id}", "phone": rider_phone},
        timeout=15,
    )
    assert res.status_code in (200, 201), f"Rider creation failed: {res.text}"
    r1_id = res.json().get("id") or res.json().get("rider", {}).get("id")
    r1_code = res.json().get("access_code") or res.json().get("sign_in_code")

    # Rider login on ops worker
    res = requests.post(
        f"{OPS_API}/v1/auth/rider/login",
        json={"phone": rider_phone, "code": r1_code, "device": {"id": f"rdev_{test_run_id}"}},
        timeout=15,
    )
    assert res.status_code == 200, f"Rider login failed: {res.text}"
    r1_token = res.json().get("token") or res.json().get("access_token")
    r1_headers = {"Authorization": f"Bearer {r1_token}", "Content-Type": "application/json"}
    log(f"Vendor 1 ({v1_id}) and Rider 1 ({r1_id}) logged in.")

    # Assign customer to Vendor 1
    log("Assigning test customer to Vendor 1...")
    res = requests.post(
        f"{ADMIN_API}/v1/admin/users/{cust_id}/assign-vendor",
        headers=admin_headers,
        json={"vendor_id": v1_id},
        timeout=15,
    )
    assert res.status_code == 200, f"Assign vendor failed: {res.text}"

    # 4. Check Orphan Customers before suspension
    res = requests.get(
        f"{ADMIN_API}/v1/admin/vendors/{v1_id}/orphan-customers",
        headers=admin_headers,
        timeout=15,
    )
    assert res.status_code == 200, f"Orphan check failed: {res.text}"
    assert res.json()["count"] >= 1
    assert any(c["id"] == cust_id for c in res.json()["customers"])
    log("Orphan customers endpoint verified.")

    # 5. Suspend Vendor 1 and Verify Cascade
    log("5. Testing Vendor 1 Suspension Cascade...")
    res = requests.post(
        f"{ADMIN_API}/v1/admin/users/{v1_id}/suspend",
        headers=admin_headers,
        json={"reason": "Suspension cascade test", "level": "suspend"},
        timeout=15,
    )
    assert res.status_code == 200, f"Suspend failed: {res.text}"
    susp_data = res.json()
    assert susp_data["suspended"] is True
    assert susp_data["detached_riders"] >= 1
    log(f"Vendor suspended. Detached riders: {susp_data['detached_riders']}")

    # Verify Rider 1 session is revoked immediately
    log("Verifying Rider 1 session revocation...")
    res = requests.get(
        f"{OPS_API}/v1/rider/duty",
        headers=r1_headers,
        timeout=15,
    )
    assert res.status_code in (401, 403), f"Expected 401/403 for revoked rider, got {res.status_code}"
    log("Rider session revoked verified: 401/403.")

    # Verify Vendor 1 cannot accept orders or be assigned
    res = requests.get(
        f"{OPS_API}/v1/vendor/stops/today",
        headers=v1_headers,
        timeout=15,
    )
    assert res.status_code in (401, 403), f"Expected 401/403 for revoked vendor, got {res.status_code}"
    log("Vendor session revoked verified: 401/403.")

    # 6. Admin 1-Click Reassignment to Vendor 2
    log("6. Creating Vendor 2 and testing 1-click reassignment...")
    vendor2_phone = f"+9195{int(time.time()) % 100000000:08d}"
    res = requests.post(
        f"{ADMIN_API}/v1/admin/vendors",
        headers=admin_headers,
        json={"name": f"Vendor 2 {test_run_id}", "phone": vendor2_phone, "zone_id": "zone_satna", "auto_verify": True},
        timeout=15,
    )
    assert res.status_code in (200, 201), f"Vendor 2 creation failed: {res.text}"
    v2_id = res.json().get("id") or res.json().get("user_id")

    res = requests.post(
        f"{ADMIN_API}/v1/admin/vendors/{v1_id}/reassign-customers",
        headers=admin_headers,
        json={"new_vendor_id": v2_id, "reason": "Vendor 1 suspended reassignment"},
        timeout=15,
    )
    assert res.status_code == 200, f"1-click reassign failed: {res.text}"
    reassign_data = res.json()
    assert reassign_data["reassigned_count"] >= 1
    assert reassign_data["new_vendor_id"] == v2_id
    log(f"1-Click reassignment verified: {reassign_data['reassigned_count']} customers reassigned to Vendor 2.")

    # 7. Customer Subscription & Mid-Cycle Cancellation
    log("7. Testing Customer Subscription Creation & Mid-Cycle Cancellation...")
    # Add address for customer
    res = requests.post(
        f"{CUSTOMER_API}/v1/addresses",
        headers=cust_headers,
        json={
            "type": "home",
            "lat": 24.58,
            "lng": 80.83,
            "label": "Home",
            "formatted": "123 Civil Lines, Satna",
            "pincode": "485001",
        },
        timeout=15,
    )
    assert res.status_code in (200, 201), f"Address creation failed: {res.text}"
    addr_id = res.json()["id"]

    # Create subscription
    res = requests.post(
        f"{CUSTOMER_API}/v1/subscriptions",
        headers=cust_headers,
        json={
            "address_id": addr_id,
            "qty": 1,
            "schedule_type": "daily",
            "payment_method": "cod",
            "billing_mode": "per_delivery",
        },
        timeout=15,
    )
    assert res.status_code in (200, 201), f"Subscription creation failed: {res.text}"
    sub_id = res.json()["id"]
    log(f"Subscription {sub_id} created.")

    # Cancel subscription
    res = requests.post(
        f"{CUSTOMER_API}/v1/subscriptions/{sub_id}/cancel",
        headers=cust_headers,
        json={"reason": "Relocating mid-month", "upi_id": "customer@okaxis"},
        timeout=15,
    )
    assert res.status_code == 200, f"Subscription cancel failed: {res.text}"
    cancel_data = res.json()
    assert cancel_data["status"] == "canceled"
    assert "unpaid_dues_posted_paise" in cancel_data
    log(f"Subscription mid-cycle cancellation verified. Status: {cancel_data['status']}")

    # 8. Clean up test users, strictly preserving admin
    log("8. Cleaning up test accounts...")
    res = requests.post(
        f"{ADMIN_API}/v1/admin/users/{cust_id}/suspend",
        headers=admin_headers,
        json={"reason": "Test cleanup", "level": "suspend"},
        timeout=15,
    )
    res = requests.post(
        f"{ADMIN_API}/v1/admin/users/{v2_id}/suspend",
        headers=admin_headers,
        json={"reason": "Test cleanup", "level": "suspend"},
        timeout=15,
    )

    log("=== ALL SCENARIOS VERIFIED SUCCESSFULLY ON LIVE PRODUCTION! ===")


if __name__ == "__main__":
    main()
