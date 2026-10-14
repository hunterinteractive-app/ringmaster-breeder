# Sales dashboard

Open **Sales dashboard** from My Herds to see the selected family's sales across its herds. From an animal list, choose **Actions → Sales dashboard** for that herd, or **Bulk mark For Sale** to list animals from the current filtered view. The bulk dialog supports searching, selecting all matching animals, and setting an optional common asking price. Each animal gets a separate listing and can be priced individually afterward.

For Sale is a sales tag, not an animal status. Listed and reserved animals remain active in breeding and show entry. The animal list includes a For Sale filter and badges. Only active, non-pedigree-only animals without an existing open listing can be added. Completing a sale marks the animal Sold using its normal historical-record protections.

The dashboard records asking and agreed prices in USD, buyer name/email/phone/address, sale date, and private notes. Listings move through For Sale, Reserved, Sold, or Cancelled. Reserved and Sold require a buyer name; Sold requires an agreed price and a sale date. Sold records remain in history; cancelled listings are read-only and can be relisted as a new sale. Listings with payments must be fully refunded before cancellation.

Payments are manual receipts, not payment processing. Record deposits, further payments, and refunds with their date, method, reference, and notes. The balance uses the agreed price when provided, otherwise the asking price. Deposits count once toward payment totals. Net received subtracts refunds; the deposit figure shows deposits originally received. No overpayment, excess refund, negative amount, or future payment date is accepted. Receipts are append-only; correct a receipt with an appropriate refund and replacement payment. An uncertain retry within the same dialog uses the same receipt ID to avoid duplicates.

Use Open, For Sale, Reserved, Sold, History, or All views and search by animal or buyer. Summary figures cover the whole selected family/herd scope, not just search results. Animals without a price do not contribute to the balance total. History records listing creation, changed sale/buyer fields, deposits, payments, and refunds with timestamps and the acting user's ID. It does not expose buyer data through pedigrees or the Show integration.

Access follows accepted family membership and is revoked immediately with family access. Clients cannot directly change or delete receipts or history. Private triggers check membership and serialize receipts against the sale row; integer cents avoid floating-point storage errors. Existing Show animals remain unchanged until a sale is completed. Verified permanent account deletion removes sale, payment, and buyer history before deleting the account's animals.

## Verification

- `flutter analyze`
- `flutter test`
- `flutter build web --release --pwa-strategy=none`
- `supabase/tests/sales_dashboard.sql`, inside a rollback-only transaction after applying the migration to an isolated database.

The database test checks duplicate listings, animal ownership, price/payment bounds, refunds, sale completion, append-only audit records, accepted family access, cross-family isolation, and revoked access. Flutter tests check exact-cent parsing, balances/refunds, unpriced animals, mobile/desktop bulk selection, retries, and dashboard layout/totals.

## Buyer pedigree email

Marking an animal Sold offers to email its pedigree. The offer appears both when completing a dashboard sale and when changing an animal status in Edit Animal. Sold sale cards and sold animal details retain an Email pedigree button. The buyer address is prefilled when a sold sale record contains it, and the user confirms before sending.

Each email attaches pedigree.pdf and pedigree.json. The server prepares an allowlisted fifteen-slot pedigree snapshot; prices, payments, private notes, buyer details, internal identifiers, and health records are excluded. The PDF is generated from that same snapshot and can be previewed. JSON uses the ringmaster-pedigree format, version 1, with named ancestry slots. This feature exports JSON; a buyer JSON-import screen is not part of this change.

Delivery follows Show's existing Resend setup through its server-only send-breeder-pedigree endpoint. Both projects already contain the same Breeder bridge server credential; no mail key is copied to Breeder or exposed to clients. Sender display name comes from the herd owner's profile. The actual From mailbox remains the verified RingMaster sender, with Reply-To set to the owner's verified Auth email. An invited family member sends on behalf of the family owner.

Draft snapshots and provider acceptance are stored in the service-only pedigree_buyer_emails table. Retrying the same dialog reuses the request ID, PDF, and recipient. The relay preserves Resend's idempotency key, and retries older than 23 hours are refused unless already accepted. Provider acceptance is logged in sale history when associated with a sale; acceptance does not confirm inbox delivery. No email is sent merely by saving a sale.
