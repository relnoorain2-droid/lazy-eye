First full build: all 32 exercises, the check-in battery, and subscriptions.

WHAT TO TEST FIRST — in this order, because each one gates the next:

1. ONBOARDING AND CALIBRATION
   Measure the screen with a credit card and set your viewing distance. Every
   stimulus size in the app is derived from this, so if it feels wrong here,
   everything after it is wrong too. The medical disclaimer will not let you
   continue without an explicit tap — that is deliberate.

2. THE PAYWALL
   Check all three prices appear ($2.99 weekly, $9.99 monthly, $29.99 yearly).
   If any are missing or the sheet is empty, the products have not finished
   propagating in App Store Connect — that is the single most likely fault in
   this build. Also tap Privacy and Terms and confirm both open.

3. RED-CYAN GLASSES — THE ONE THING ONLY YOU CAN CHECK
   Profile -> Red-cyan glasses -> "Check they're working". Put the glasses on.
   Each eye should see its own symbol and NOT the other's. Faint ghosting is
   normal; clearly seeing both symbols with one eye is not. The maths behind
   this is tested, but whether real glasses on this panel actually separate is
   a physical fact no test can settle.

4. ONE EXERCISE FROM EACH TRACK
   A single-eye one (Landolt C), a two-eye one (Depth Pop, glasses on), and a
   game (Balloon Pop). Watch for anything that looks too small to see or too
   large to be a challenge — that is a calibration problem, not a taste one.

5. THE CHECK-IN
   Today -> Check-in. Four short measurements, about six minutes. It should end
   by itself. If it ever seems to repeat the same eye test, stop and tell me:
   that exact hang was fixed in this build and I want to know if it survived.

KNOWN AND DELIBERATE
- Assessment sub-tests show numbered answer buttons rather than each exercise's
  own stimulus view. The measurement path is complete; the presentation is not.
- No launch screen art or alternate icons yet.
