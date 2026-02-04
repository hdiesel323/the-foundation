# Procurement Tracker

## Active Supplier Pipeline

| Supplier | Product | Stage | Score | MOQ | Unit Cost | Lead Time | Next Action | Due |
|----------|---------|-------|-------|-----|-----------|-----------|-------------|-----|
| {{supplier}} | {{product}} | {{stage}} | {{score}}/100 | {{moq}} | ${{cost}} | {{days}}d | {{action}} | {{date}} |

### Pipeline Stages
1. **Sourcing** — Initial contact and catalog review
2. **Sample** — Samples requested/in transit
3. **Evaluation** — Samples received and under review
4. **Negotiation** — Terms and pricing discussion
5. **PO** — Purchase order issued

## Order Status Tracking

| PO# | Supplier | Products | Qty | Value | Status | Ship Date | ETA | Tracking |
|-----|----------|----------|-----|-------|--------|-----------|-----|----------|
| {{po_number}} | {{supplier}} | {{products}} | {{qty}} | ${{value}} | {{status}} | {{ship_date}} | {{eta}} | {{tracking}} |

### Order Statuses
- **Pending** — PO issued, awaiting confirmation
- **Confirmed** — Supplier confirmed, production started
- **Production** — Manufacturing in progress
- **QC** — Pre-shipment inspection
- **Shipped** — In transit
- **Customs** — At customs clearance
- **Received** — Delivered to warehouse
- **Closed** — Inventory counted and reconciled

## Sample Evaluation Log

| Date | Supplier | Product | Quality | Build | Color Accuracy | Heat | Score | Verdict |
|------|----------|---------|---------|-------|----------------|------|-------|---------|
| {{date}} | {{supplier}} | {{product}} | {{1-5}} | {{1-5}} | {{1-5}} | {{1-5}} | {{total}}/20 | {{pass_fail}} |

### Evaluation Criteria
- **Quality** (1-5): Overall build quality, materials, finish
- **Build** (1-5): Structural integrity, joint quality, weight
- **Color Accuracy** (1-5): CRI, color temp accuracy, consistency
- **Heat** (1-5): Heat management (5 = cool running, 1 = overheating)
- **Pass threshold**: 14/20 minimum

## Budget Summary

| Category | Budget | Committed | Spent | Remaining |
|----------|--------|-----------|-------|-----------|
| Samples | ${{sample_budget}} | ${{committed}} | ${{spent}} | ${{remaining}} |
| Inventory | ${{inv_budget}} | ${{committed}} | ${{spent}} | ${{remaining}} |
| Shipping | ${{ship_budget}} | ${{committed}} | ${{spent}} | ${{remaining}} |
| **Total** | **${{total}}** | **${{committed}}** | **${{spent}}** | **${{remaining}}** |
