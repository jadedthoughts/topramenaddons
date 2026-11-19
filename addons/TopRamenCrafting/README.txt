Top Ramen Crafting
==================

An in-game crafting planner for WoW Forever. It tells you what to craft to level a
profession, what makes money, and exactly what to buy, using today's auction house
and vendor prices. Works with any crafting profession, plus First Aid and Cooking.

INSTALL
Copy the folder "TopRamenCrafting" into World of Warcraft\_forever_\Interface\AddOns\
No other addons are needed. If Auctionator is installed, its prices are used for
anything Top Ramen hasn't scanned yet.

GETTING STARTED
1. Type /trc (or /topramencraft) to open the planner.
2. At the auction house, click Full scan in the planner's header.
3. Click each profession button along the top once. It opens that profession and
   records its recipes. A check mark means its recipes are current; a red X means
   they need reading again (you've gained skill, or you pressed Refresh). Click it.

SETTINGS
- Sell to: vendor (instant), best price, or auction house
- Points to plan / Max price age (days): type a number, or use - and +
- Use my materials first: count what's in your bags and bank as already paid for
- Make reagents myself when cheaper: craft Cured Hides etc. yourself when that saves
  enough to be worth the extra crafting
- Best chance for skill-ups (on by default): always use the recipe most likely to give
  a point (orange first, then the best yellow). Off: the cheapest route, which may mean
  many green crafts.

TABS
- Skill-up plan: the crafts for your next points, worked out at the skill you'll have
  as you go. Rows show "orange until ~130" or "gray at 155". The game reports the gray
  level; the yellow point starts as an estimate and is learned as you level.
- Money makers: crafts that profit even if you buy every material. Tick one and set how
  many to make.
- Shopping list: only the crafts you've ticked. Shows what to craft first, what to buy
  and where, a grand total, your gold, what's left after buying, and what you'll have
  after vending what you craft. Hover a material to see what it's for.
  "Clear all selected" unticks everything.
- Vendor flips: everything on the auction house priced below what a vendor pays for it,
  from your last scan, with the profit if you buy those listings and vendor them. With
  the auction house open, Open shows the item in the auction window. Cheap listings sell
  fast, so run a Full scan right before.
  Tick items to add them to the Shopping list under "Vendor flips"; the Auctionator
  list caps their price so only listings below what a vendor pays show. "Reagents only" narrows the list.
- Guild: every profession in your guild and who has it, online people first (offline
  members included). When someone links a profession in chat, the addon saves the link
  and, once you open it, their skill and recipe list. The search box finds a
  guildmate by name, or who can make a recipe. Click a profession heading to fold it. Open (online guildmates only; the game won't open an offline
  person's profession) shows their profession window: it reopens a saved link, or builds
  one from their guild roster entry (Link column "can build") without them linking it.
  Built links only open for guildmates whose character ID has the same server number
  as yours. For the rest ("needs their link"), Open appears once they've linked a
  profession in chat. The Refresh guild
  list button (bottom) shows when the list was last read: green check within 15
  minutes, yellow ? within a day, red X older. Click it to read the list again.

BUYING AT THE AUCTION HOUSE
Buying goes through Auctionator. On the Shopping list tab, click "Create Auctionator
list": it makes an Auctionator shopping list with every auction house item and the
amount to buy (vendor flips carry a price cap so only profitable listings show).
At the auction house, open Auctionator's Shopping tab and search that list.

PRICES BY QUANTITY
Scans save each item's price levels (how many are listed at each price), so the
planner prices big amounts realistically: the 50th Raptor Egg costs what the 50th
cheapest listing costs. The skill-up plan moves to other recipes when a material's
cheap listings run out, and the Shopping list shows the tiers under each auction house
item, with a note when you could buy the good-price part now and wait for the rest.
(If Auctionator is installed, "Create Auctionator list" is also available.)

AUCTION HOUSE PRICES
- Full scan: reads every listing on the auction house and saves each item's lowest
  price and how many are listed. The game allows it once every 15 minutes.
- Quick scan: searches just the materials and products your recipes use. No cooldown.
- Vendor prices are saved automatically whenever you open a vendor.
- The badge next to the scan buttons shows how fresh the prices are:
  green check = scanned in the last 15 minutes, yellow ? = up to a day old,
  red X = older than a day (or never scanned).

The window can be moved and resized from its bottom-right corner. Refresh (top right)
re-reads your bags, bank and prices and marks every profession for re-reading.

COMMANDS (/trc and /topramencraft work the same)
/trc                 open or close the planner
/trc opacity 85      window background opacity, 30-100 (default 92)
/trc reset           move the window back to the center at its default size
/trc export          text snapshot of your recipes and prices (for troubleshooting)
/trc debug           what the addon can see
/trc inspect <name>  everything the game reports about one recipe (profession window open)
/trc relink <name> <profession>   reopen a profession link someone sent (close spellings work)

The addon never buys anything without your Buy Now and Confirm clicks, and never sells,
crafts or moves items.
