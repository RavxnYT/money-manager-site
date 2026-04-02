# Team collaboration — frozen v1 specification

Product rules for **Business Pro** org workspaces: invites, roles, seats, and access when Pro lapses.  
Enforce **server-side** (e.g. Supabase RLS + membership tables); the app must not be the only gate.

---

## Team composition

| Role        | Count per org | Pro required                         |
|------------|----------------|--------------------------------------|
| **Owner**  | Exactly **1**  | **Yes** — pays; org Pro follows this subscription |
| **Co-owner** | **0 or 1**   | **No** — org premium features still apply while Owner’s Pro is active |
| **Member** | **0–5**        | **No** — typical collaborators      |

**Non-owner headcount:** At most **6** people (**1 Co-owner + 5 Members**) plus the Owner.

---

## Seat pools and invites

### Member pool (5)

- Counts: **active Members** + **pending invites** issued for role **Member**.
- **Revoke** or **expire** a pending Member invite → **seat refunded**.
- **Remove** a Member → seat refunded.

### Co-owner slot (1)

- At most **one** Co-owner **or** **one pending Co-owner invite** at a time (pending invite occupies the slot until accepted, revoked, or expired; **revoke → slot refunded**).
- **Demote** Co-owner → Member or **remove** Co-owner → slot freed.  
  If demoting to Member would exceed **5** Members, **block** until a Member seat is free.

### Owner

- Does **not** consume Member or Co-owner slots.

### Invite rules

- **Flexible** invite email; **acceptance must verify** identity (e.g. magic link / email proof — implementation detail).
- **Default role on accept:** **Member** (unless the invite explicitly targets **Co-owner** and the co-owner slot is free).
- **Owner** and **Co-owner** may: **invite**, **revoke invites**, **remove members**, **change roles** (within constraints below).

---

## Role permissions

| Action | Owner | Co-owner | Member |
|--------|:-----:|:--------:|:------:|
| View / create / edit org data (accounts, transactions, goals, loans, budgets, bills, recurring, categories, …) | Yes | Yes | Yes |
| **Delete** org-scoped data | Yes | Yes | **No** |
| Org / team **settings** | Yes | Yes | **No** |
| **Invite / revoke / remove / change roles** | Yes | Yes | **No** |
| **Delete org** (after verification) | Yes | **No** | **No** |
| **Transfer ownership** (recipient must have **Pro**) | Yes | **No** | **No** |
| **Subscription / billing** | Yes | **No** | **No** |

### Org premium features

Features tied to Pro for the org (e.g. advanced reports, CSV export, category branding):

- **Owner** and **Co-owner:** **Yes**, while the org’s **Owner subscription (Pro) is active**.
- **Member:** **No**, even when the org is paid.

---

## Co-owner

- **At most one** Co-owner per org.
- Same capabilities as Owner **except:** cannot **delete org**, cannot **transfer ownership**, cannot **manage billing**.
- May **invite**, **revoke**, **remove**, and **promote/demote** roles subject to **Member (5)** and **Co-owner (1)** limits.

---

## Org deletion

- **Owner only**, only after **verification** (e.g. password + confirm org name).

---

## Ownership transfer

- Allowed **only** if the **recipient has Pro**.
- Define in implementation how **billing and org subscription** attach after transfer.  
  Suggested default: **previous Owner** becomes **Member** unless they explicitly leave the org.

---

## Subscription lapse (Owner’s Pro inactive)

| Role     | Org access |
|----------|------------|
| **Owner**   | **Read-only**; **no** edits, **no** invites, **no** role changes until Pro is restored. **Restore by paying** (resubscribe). |
| **Co-owner** | **Read-only** until Owner restores Pro (Co-owner cannot replace Owner’s billing unless product adds that). |
| **Member**   | **No access** to the org. |

Data is **retained**; only **access policy** changes.

---

## Summary constraints

1. **5** Member seats (active Members + pending Member invites); revoke/refund applies.  
2. **1** Co-owner slot; pending Co-owner invite follows same “occupy slot / revoke refunds” pattern.  
3. **Members:** **no** settings, **no** delete.  
4. **Co-owner:** same as Owner except **no** delete org, **no** transfer ownership, **no** billing.  
5. **Premium org features:** **Owner + Co-owner** only while Owner’s Pro is active.  
6. **Transfer:** only to a user **with Pro**; verified org delete **Owner-only**.

---

*Document version: v1 (frozen for implementation).*
