/** First regular renewal on/after a catalogue start date; never cuts a paid term short. */
export function priceChangeRenewal(sub: any, notBefore: string): number {
  const item = sub.items?.data?.[0];
  if (!item || sub.items.data.length !== 1 || item.quantity !== 1) {
    throw Error(
      "Review this subscription configuration before changing its price.",
    );
  }
  const end = item.current_period_end ?? sub.current_period_end;
  const interval = item.price?.recurring?.interval;
  if (
    !end || !["month", "year"].includes(interval) ||
    item.price.recurring.interval_count !== 1
  ) {
    throw Error("Unsupported renewal interval.");
  }
  const cutoff = Date.parse(notBefore) / 1000;
  if (!Number.isFinite(cutoff)) throw Error("Invalid price start date.");
  const anchor = new Date((sub.billing_cycle_anchor ?? end) * 1000);
  const first = new Date(end * 1000);
  for (let n = 0; n < 1201; n++) {
    const month = first.getUTCMonth() + (interval === "month" ? n : n * 12);
    const last = new Date(Date.UTC(first.getUTCFullYear(), month + 1, 0))
      .getUTCDate();
    const date = n === 0 ? first : new Date(
      Date.UTC(
        first.getUTCFullYear(),
        month,
        Math.min(anchor.getUTCDate(), last),
        first.getUTCHours(),
        first.getUTCMinutes(),
        first.getUTCSeconds(),
      ),
    );
    if (date.getTime() / 1000 >= cutoff) return date.getTime() / 1000;
  }
  throw Error("Price start date is too far ahead.");
}
export function noticeText(notice: any, oldPrice: any, newPrice: any): string {
  const tier = ({
    HOBBY: "Hobby Breeder",
    PRO: "Professional Breeder",
    TOP: "Top Tier",
  } as any)[newPrice.tier_code];
  const money = (p: any) =>
    `$${(p.amount_cents / 100).toFixed(2)} USD/${
      p.interval === "year" ? "year" : "month"
    }`;
  const date = new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/Indiana/Indianapolis",
  }).format(new Date(notice.effective_at));
  return `Hello,\n\nYour RingMaster Breeder ${tier} membership price will change from ${
    money(oldPrice)
  } to ${
    money(newPrice)
  } on ${date} (Eastern Time), at your renewal.\n\nYour current price continues until that date. No immediate charge is made for this change. Any applicable tax is additional.\n\nYou can review your membership, update your payment method, or cancel future renewals before that date in Account > Subscription > Manage membership & billing:\nhttps://breeder.ringmasterone.com/\n\nThank you,\nRingMaster Breeder`;
}
