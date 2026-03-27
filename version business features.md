# Money Manager Business Pro — Professional Growth Plan

## 1) Product Vision

Money Manager stays a great free personal finance app, while **Business Pro** turns it into a serious operating layer for founders, freelancers, teams, and small businesses.

- **Single app model:** all Business Pro capabilities ship in the same app build.
- **Unlock model:** business capabilities unlock at runtime through RevenueCat entitlements.
- **Mode model:** users can switch between **Personal** and **Business** using one Settings toggle.
- **Scalable path:** launch with high-value features first, then evolve into collaboration/workspace architecture.

## 2) Positioning & Strategy

### Free (Personal)
- Core tracking, budgets, categories, and reports.
- Great for individual users.

### Business Pro (Paid)
- Advanced operations, automation, export workflows, and business analytics.
- Designed to feel like a lightweight finance OS, not just a tracker.

### Business Pro Principles
- Fast to understand.
- Powerful but controlled.
- Audit-friendly.
- Reliable offline behavior.

## 3) Monetization Setup (RevenueCat)

### Billing stack
- `purchases_flutter`
- `purchases_ui_flutter`

### Planned commercial configuration
- Offering: `default` (confirmed in RevenueCat paywall settings)
- Packages:
  - `monthly`
  - `yearly`
- Trial:
  - 7-day free trial (attached at store product level)

### Required identifiers (confirmed)
- Entitlement ID (exact): `Money Manager Pro`
- Entitlement REST API Identifier: `ent122b7de64a9`
- Monthly package ID: `monthly`
- Yearly package ID: `yearly`

## 4) Runtime Access Model (important)

### Business features are pre-installed
No separate app install. Business features already exist in UI/code and are simply gated.

### Unlock rule
Business features are enabled only if:
- RevenueCat Pro entitlement is active
- AND `business_mode_enabled` is true in profile (user selected Business mode)

### One-button mode switching in Settings
- If user enables Business mode:
  - If entitlement active -> enable instantly.
  - If entitlement inactive -> open paywall; enable only after successful purchase.
- If user enables Personal mode:
  - Keep entitlement intact, but hide business-only UI and behavior.

## 5) Core Business Pro Feature Set (launch)

## A) Ad-free professional experience
- Hide support ad prompts and ad-related UX when in Business mode with active entitlement.

## B) Advanced category branding
- Business users can choose custom category icon and color.
- Free users keep auto-assigned defaults.
- Categories become report-friendly visual primitives (branding + clarity).

## C) Advanced reports and operating dashboards
- Extended time windows (3/6/12 months).
- Category trend views.
- Account-level performance breakdown.
- KPI cards (net burn, income concentration, spend volatility).

## D) Export workflows
- CSV export (phase 1 launch requirement).
- PDF export (phase 2).
- “Export-ready summary” cards tailored for accountant/shareholder updates.

## E) Capacity scaling
- Free: lower limits (accounts/categories).
- Business Pro: higher or unlimited thresholds.
- Enforced at repository level to keep logic consistent.

## 6) “Crazy” Differentiators (unique, high-impact)

These are features most finance apps either do not have or do poorly. They make your app stand out.

## 1. Finance Copilot Timeline
- A narrative “what changed this week/month” feed:
  - spike alerts
  - unusual category shifts
  - income drop warnings
  - suggested actions
- Converts raw numbers into business decisions.

## 2. Scenario Simulator (“What if?”)
- Users test scenarios before spending:
  - “If rent increases by 12%, what happens to runway?”
  - “If I hire 1 person, how does monthly net change?”
- Gives forward-looking planning, not only historical tracking.

## 3. Smart Anomaly Detection
- Detects abnormal expenses by account/category/user-defined thresholds.
- Supports “risk flags” and optional lock-step approvals in team mode.

## 4. Runway & Survival Meter
- Calculates how many months business can survive at current burn.
- Visual stress meter + recommendations to extend runway.

## 5. Cashflow Storyboard
- A visual monthly storyboard (income waves, fixed costs, variable leaks).
- Makes executive communication easier for non-finance team members.

## 6. Policy Rules Engine (lightweight)
- User-defined rules:
  - “Warn me if dining > X per month”
  - “Flag transactions above Y”
  - “Block export unless reconciled”
- Turns app into a finance governance tool.

## 7. Audit Trail Events
- Immutable event trail for edits/deletes/major actions (business mode).
- Useful for accountability and future team collaboration.

## 8. Smart Closing Checklist
- Month-end checklist:
  - pending bills
  - uncategorized transactions
  - anomalies unresolved
  - export status
- Helps users run a professional finance close process.

## 9. Multi-entity foundation
- Support “workspaces” later (Personal + Business A + Business B).
- Smooth path to serious team/accounting workflows.

## 10. AI-driven category healing
- Suggest recategorization for messy historic data.
- Improves report quality over time.

## 11. Industry Payments Command Center
- A dedicated operations screen used by real finance teams to control outgoing and incoming money.
- Includes:
  - scheduled payables and receivables
  - failed/returned payments
  - pending approvals
  - settlement status
  - exceptions requiring manual action

## 12. Multi-level Approval Matrix (maker-checker)
- Real finance organizations do not release payments with one click.
- Add configurable approval paths:
  - low amount: manager
  - medium amount: finance lead
  - high amount: controller/CFO
- Add maker-checker policy:
  - preparer cannot be final approver.

## 13. Batch Payment Orchestrator
- Group payments into release windows (daily/weekly).
- Approve and release in controlled batches.
- Add controls:
  - pause batch
  - partial release
  - rollback before release
- Useful for payroll-like and large vendor payment cycles.

## 14. Vendor Ledger + Counterparty Risk Layer
- Vendor/customer profile with:
  - payment terms
  - preferred currency
  - expected settlement window
  - dispute history
- Add risk scoring for counterparties with repeated delays/chargebacks/anomalies.

## 15. 2-way / 3-way Match Engine
- Industry-grade accounts payable control:
  - 2-way: invoice vs PO
  - 3-way: invoice vs PO vs goods received
- Block or flag mismatched payments before release.

## 16. AR Dunning Automation
- Automated collections pipeline:
  - reminder 1
  - reminder 2
  - escalation
  - final notice
- Track:
  - DSO (days sales outstanding)
  - aging buckets
  - collection hit-rate.

## 17. 13-Week Cash Forecast (treasury standard)
- Rolling treasury forecast used by finance leaders.
- Scenarios:
  - base case
  - conservative case
  - stress case
- Connects recurring costs, expected receivables, and scheduled payables.

## 18. Reconciliation Hub with Exception Queue
- Reconciliation states:
  - matched
  - suggested
  - unmatched
  - exception
- Add exception queue for fast close and audit readiness.

## 19. FX Exposure Radar
- For multi-currency businesses:
  - open exposure by currency
  - projected FX impact on net position
  - threshold alerts for hedge review.

## 20. Payment Fraud Signal Layer
- Risk alerts for:
  - payee changes
  - duplicate invoice patterns
  - unusual timing/amount spikes
  - new beneficiary high-value payments
- High-risk transactions require additional approval.

## 21. Audit Evidence Pack
- One-click export for external audit:
  - approval history
  - transaction lineage
  - reconciliation proof
  - policy rule outcomes
- Reduces audit preparation time massively.

## 7) Technical Architecture Plan

## Phase 1 — RevenueCat integration
1. Add packages via pub.
2. Add API key in `.env`.
3. Create `revenuecat_service.dart`:
   - configure
   - login/logout sync with Supabase user id
   - customer info retrieval
   - entitlement checks
4. Add customer info listener for real-time unlock updates.

## Phase 1.5 — Paywall & customer management
1. Use `presentPaywallIfNeeded("Money Manager Pro")`.
2. Add Customer Center entry point.
3. Add restore purchases flow.

## Phase 2 — Profile entitlement persistence
Add profile fields:
- `business_mode_enabled` boolean default false
- `business_pro_status`
- `business_pro_updated_at`
- `business_pro_latest_expiration`
- `business_pro_platform`

Repository additions:
- `isBusinessPro()`
- `refreshBusinessEntitlement()`
- `setBusinessModeEnabled(bool)`

## Phase 3 — UI gating
Settings:
- Business Plan card
- Upgrade/manage/restore actions
- One-button Personal/Business switch

Global gating helpers:
- entitlement-only gate
- mode+entitlement gate

## Phase 4 — Feature rollout
Launch order:
1. Ad-free
2. Custom category branding
3. Advanced reports
4. CSV export
5. Limits upgrade
6. Differentiators batch 1 (copilot timeline + runway + anomalies)
7. Industry controls batch 2 (approval matrix + batch payments + reconciliation)
8. Treasury/risk batch 3 (13-week forecast + FX exposure + fraud signals)

## Phase 5 — Collaboration foundation
Future schema:
- organizations
- organization_members
- role-based RLS
- workspace selector

## 8) Business UX Design Standards

- Professional, minimal, high-trust copy.
- Avoid gimmicky wording.
- Explain value using outcomes:
  - save time
  - avoid mistakes
  - improve decision quality
- Every premium action should have:
  - clear benefit
  - clear fallback in free mode
  - clear upgrade path (one tap)

## 9) Risk & Mitigation

## Risk: entitlement mismatch
- Mitigation: periodic refresh + listener + manual restore.

## Risk: users confused by mode switch
- Mitigation: clear helper text under toggle:
  - “Personal mode hides business-only tools”

## Risk: overpromising on team features
- Mitigation: ship “foundation” wording first; mark collaboration as “coming soon” unless fully implemented.

## 10) QA and Test Strategy

## Unit tests
- Entitlement parsing
- Gate condition logic
- Mode toggle behavior

## Widget tests
- Business card visibility and state rendering
- Paywall trigger behavior
- Category icon editor gated by entitlement

## Integration tests
- Test-only override:
  - `--dart-define=E2E_FORCE_BUSINESS_PRO=true`
- Validate end-to-end business flow without real billing.

## 11) Launch Readiness Checklist

- RevenueCat offering/packages configured.
- Entitlement linked to paywall.
- Business mode toggle behavior verified.
- Restore purchases and Customer Center working.
- Free mode unaffected and stable.
- Export + report performance acceptable on real devices.

## 12) Success Metrics (post-launch)

- Paywall view -> trial start conversion.
- Trial -> paid conversion.
- Monthly churn and downgrade rates.
- Percentage of active users using Business mode.
- Export usage and advanced report usage.
- Retention uplift for Business users vs free users.
- Approval cycle time.
- Payment exception resolution time.
- On-time vendor payment rate.
- DSO improvement for receivables users.

## 13) File Map (planned execution)

- Billing SDK and services
  - `pubspec.yaml`
  - `lib/main.dart`
  - `lib/src/core/billing/*`
- Settings/business controls
  - `lib/src/features/settings/settings_screen.dart`
  - `lib/src/features/billing/*`
- Gated business features
  - `lib/src/features/categories/categories_screen.dart`
  - `lib/src/features/reports/reports_screen.dart`
  - `lib/src/features/transactions/transactions_screen.dart`
- Data and persistence
  - `lib/src/data/app_repository.dart`
  - `supabase/schema.sql`
  - `supabase/migrations/*`

## 14) Final Principle

Money Manager should feel like:
- **simple enough** for personal users,
- **powerful enough** for business operators,
- and **credible enough** to be trusted as a finance command center.

