"""Emit patched execute_entity_transfer (org-scoped) for team migration."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
schema = (root / "supabase" / "schema.sql").read_text(encoding="utf-8")
end = schema.rfind("create or replace function public.run_due_recurring_transactions")
if end == -1:
    raise SystemExit("anchor not found")
chunk = schema[:end]
start = chunk.rfind("create or replace function public.execute_entity_transfer(")
if start == -1:
    raise SystemExit("execute_entity_transfer not found")
block = schema[start:end].rstrip() + "\n"

if "p_organization_id uuid default null" not in block:
    raise SystemExit("wrong execute_entity_transfer slice")

block = block.replace(
    "declare\n  v_fk text",
    "declare\n  v_sub uuid;\n  v_fk text",
)
block = block.replace(
    "perform public.assert_workspace_access(p_user_id, p_organization_id);\n\n",
    "perform public.assert_workspace_access(p_user_id, p_organization_id);\n"
    "  v_sub := public.workspace_row_subject_user_id(p_user_id, p_organization_id);\n\n",
)
block = block.replace("and user_id = p_user_id", "and user_id = v_sub")
block = re.sub(
    r"perform public\.create_transaction\(\s*\n\s*p_user_id,",
    "perform public.create_transaction(\n      v_sub,",
    block,
)
for fn in ("add_savings_progress", "refund_savings_progress", "record_loan_payment"):
    block = re.sub(
        rf"perform public\.{re.escape(fn)}\(\s*\n\s*p_user_id,",
        f"perform public.{fn}(\n      v_sub,",
        block,
    )

# Not under migrations/: only files matching <timestamp>_name.sql are applied;
# merged by hand into 20260402103100_team_collaboration_rpcs.sql (or copy from here when refreshing).
out = root / "supabase" / "scripts" / "_generated_entity_transfer_fragment.sql"
out.write_text(block, encoding="utf-8")
print("wrote", out.relative_to(root), "v_sub count:", block.count("v_sub"))
