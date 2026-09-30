# Small Business Management App — UI/UX & Product Specification

## 1. Product Overview

This is a mobile-first business operations app for small and growing business owners.

The app helps a business owner manage the complete lifecycle of a sale:

**Customer conversation → Order → Product availability → Payment → Delivery → Delivery confirmation → Completed transaction**

The app combines:

- WhatsApp AI customer communication
- Automatic transaction extraction from conversations
- Manual transaction creation
- Product/catalog management
- Payment tracking
- Delivery management
- Multiple logistics partners
- Personal/manual delivery confirmation
- Transaction history
- Weekly/monthly business records
- Business reports

The customer does **not** need an account in the first version. The primary users are:

1. Business owners
2. Logistics organizations
3. Logistics riders/staff

---

# 2. Design Direction

The UI should combine the two supplied reference designs:

### Reference 1 — Authentication UI
Use the first reference for:

- Login
- Create account
- Password/OTP recovery
- Onboarding forms
- Soft, clean mobile layout
- Large rounded form fields
- Soft lavender/light gradient background
- Purple primary action button
- Spacious vertical layout
- Simple social/alternative sign-in treatment where appropriate

### Reference 2 — Main App UI
Use the second reference for:

- Dashboard structure
- Rounded information cards
- Large summary card near the top
- Quick-access service cards
- Recent activity/transactions
- Bottom navigation
- Clean white/off-white background
- Strong section headings
- Compact icons
- Clear numeric summaries
- Simple, premium fintech-style spacing

### Overall visual language

The app should feel:

- Clean
- Modern
- Professional
- Fast
- Trustworthy
- Easy for non-technical business owners

Avoid making the interface look like an accounting application with too many tables. Use cards, sections, status chips, icons, and simple summaries.

---

# 3. User Roles

## 3.1 Business Owner

The main user.

Can:

- Manage business profile
- Connect WhatsApp
- Configure AI
- Create manual transactions
- Review AI-generated transactions
- Manage products
- Track payments
- Request delivery
- Select/use logistics providers
- Personally deliver orders
- Confirm delivery manually
- View transaction history
- View reports

## 3.2 Logistics Organization

A logistics business partnered with the platform.

Can:

- Manage organization profile
- Define service locations
- Receive delivery requests
- Accept/reject deliveries
- Assign riders
- Track active deliveries
- Update delivery status
- Submit proof of delivery
- View completed/failed deliveries
- Manage rider accounts

## 3.3 Rider / Delivery Staff

Can:

- See assigned deliveries
- View pickup information
- View customer delivery information
- Update delivery status
- Enter customer OTP
- Upload proof of delivery
- Mark delivery as failed with a reason

---

# 4. Authentication / Login Design

The authentication screens should follow the first supplied reference.

## 4.1 Login Screen

### Header
- Back button where appropriate
- App logo
- Minimal top spacing

### Main content

**Welcome back**

Small supporting text:

> Sign in to manage your business, transactions and deliveries.

Fields:

- Phone number / Email
- Password

Secondary actions:

- Forgot password?
- Remember me

Primary button:

**Log in →**

Optional:

- Continue with Google
- Continue with Apple

The social options should remain secondary to the main phone/email login.

---

# 5. Create Account / Sign Up

Use the same visual language as the first reference.

### Screen 1 — Account Type

Title:

**Create your account**

Subtitle:

> Choose how you will use the platform.

Cards:

### Business
**Manage your sales, customers, payments and deliveries.**

### Logistics Partner
**Manage deliveries for businesses on the platform.**

### Rider
**Manage deliveries assigned to you.**

The selected card gets a clear border/highlight.

---

# 6. Business Owner Onboarding

After selecting **Business**, collect:

### Basic information

- Full name
- Business name
- Phone number
- Email
- Password

### Business details

- Business category
- Business description
- Business location
- Operating address
- Business hours

### Location

Ask for location early because it affects logistics matching.

Text:

> **Where is your business located?**
>
> We'll use your location to connect you with suitable logistics partners operating near you.

Options:

- Use current location
- Enter address manually
- Select city/area

The app should store a structured location, not only a text address.

---

# 7. Logistics Partner Onboarding

When the user selects **Logistics Partner**, collect:

- Organization name
- Contact person
- Phone
- Email
- Password
- Business address
- Primary operating city
- Service areas
- Delivery types
- Pricing model
- Operating hours
- Number of riders
- Organization documents/verification where required

### Multiple logistics companies

The app must support many logistics organizations in the same city.

Example:

**Warri**
- Logistics Partner A
- Logistics Partner B
- Logistics Partner C

**Port Harcourt**
- Logistics Partner D
- Logistics Partner E

The platform must not hard-code one logistics company per location.

The business-side delivery matching system should be able to compare available partners based on:

- Service area
- Availability
- Distance
- Delivery type
- Price
- Capacity
- Partner status
- Other future routing rules

---

# 8. Main App Navigation

The main navigation should be extremely clear.

Recommended bottom navigation:

1. **Home**
2. **Transactions**
3. **AI / Chats**
4. **Logistics**
5. **Profile**

A prominent floating/center action can be:

**+ New Transaction**

The button should remain accessible without covering navigation.

---

# 9. Home Dashboard

Use the second supplied reference as the structural inspiration.

## Top header

Left:

- Business avatar/logo
- Greeting
- Business name

Example:

> Hello,  
> **ABC Fashion Store**

Right:

- Notifications
- AI status / WhatsApp connection icon

Optional small indicator:

**WhatsApp Connected ✓**

---

# 10. Business Summary Card

Large rounded card beneath the header.

Display:

**Total Sales**

`₦869,699.06`

Under the amount:

- This week
- This month
- Compare to previous period

Actions:

- View report
- View transactions

Important: this card represents business performance, not a bank account balance.

---

# 11. Quick Actions

Use compact cards similar to the "Top services" section in the second reference.

Recommended:

### New Transaction
Create a manual sale.

### Transactions
Open all transactions.

### WhatsApp AI
Open chats and AI activity.

### Products
Manage products and prices.

### Payments
Review payment activity.

### Logistics
Manage deliveries.

### Customers
View customer records.

### Reports
View business analytics.

---

# 12. Dashboard Status Cards

Add a horizontally scrollable status section.

Examples:

**Pending Payment**
12

**Awaiting Delivery**
8

**In Transit**
5

**Completed**
87

**Failed**
3

These are shortcuts. Tapping a card opens the corresponding filtered list.

---

# 13. Recent Transactions

Use the second reference's "Recent transactions" pattern.

Section title:

**Recent Transactions**

Show:

- Customer name
- Main product / number of items
- Amount
- Payment status
- Delivery status
- Date

Example:

**John Doe**
2 × Black Shirt + 1 × Blue Jeans
**₦68,000**
`Paid • Awaiting Delivery`

At the right:

**See all →**

---

# 14. Transaction System

Transactions must be unified.

Transactions can originate from:

- WhatsApp AI
- Manual creation

Both go into the same transaction database.

Each transaction has a source:

`WhatsApp` or `Manual`

---

# 15. Transaction Structure

Every transaction must contain itemized products.

Example:

**Transaction #1045**

### Customer
- Name: John Doe
- Phone: 080XXXXXXXX

### Products

| Product | Quantity | Unit Price | Subtotal |
|---|---:|---:|---:|
| Black Shirt | 2 | ₦15,000 | ₦30,000 |
| Blue Jeans | 1 | ₦25,000 | ₦25,000 |
| Cap | 2 | ₦5,000 | ₦10,000 |

Subtotal: **₦65,000**

Delivery fee: **₦3,000**

Total: **₦68,000**

Optional:

- Discount
- Tax
- Notes

---

# 16. Product Availability Before Payment

A transaction can be created before payment.

Example:

Customer requests:

- 2 shirts
- 1 pair of shoes

The AI or business owner creates the transaction.

Status:

**Order: Pending / Confirmed**

The business owner can verify stock first.

Only after the business confirms availability should the order proceed to payment.

---

# 17. Transaction Status Architecture

Do NOT use one giant status field.

Use separate status groups.

## Order Status

- Pending
- Confirmed
- Cancelled

## Payment Status

- Unpaid
- Payment Pending
- Paid
- Failed
- Refunded

## Delivery Status

- Not Required
- Pending
- Accepted
- Picked Up
- In Transit
- Delivered
- Failed

## Completion Status

- Open
- Completed

Example:

> Order: Confirmed  
> Payment: Paid  
> Delivery: Pending  
> Completion: Open

This clearly shows that receiving payment does not automatically close the transaction.

---

# 18. WhatsApp AI Section

Bottom navigation item:

**AI / Chats**

This should feel like a conversation inbox, but business-focused.

## Chat list

Each conversation can show:

- Customer
- Latest message
- Time
- AI status
- Transaction status
- Unread count

Example:

**John Doe**
"I'll take 2 of the black shirts..."
`Order #1045 • Awaiting Payment`

---

# 19. AI Conversation View

Top:

- Customer name
- Phone
- AI enabled/disabled status

Conversation below.

A transaction panel can be displayed alongside or above the chat:

**Order detected**

- 2 × Black Shirt — ₦30,000
- 1 × Blue Jeans — ₦25,000
- Total — ₦55,000
- Delivery — Required

Actions:

**Review Order**

**Create Transaction**

**Take Over Chat**

---

# 20. AI Safety / Human Override

The business owner must always be able to take control.

Provide:

**AI Active**

Toggle:

`ON / OFF`

Button:

**Take Over Conversation**

When manually taking over, the AI stops sending automatic replies until re-enabled.

This is important for:

- Complaints
- Negotiations
- Refunds
- Special requests
- Unusual orders
- Sensitive situations

---

# 21. Manual Transaction

Main action:

**+ New Transaction**

Form:

### Customer
- Name
- Phone

### Products
- Search product
- Add product
- Quantity
- Unit price
- Subtotal

Button:

**+ Add another product**

### Charges

- Subtotal
- Discount
- Delivery fee
- Total

### Delivery

**Delivery required?**

- No
- Yes

If yes:

- Delivery address
- Customer location
- Preferred delivery method

### Notes

Then:

**Create Transaction**

---

# 22. Payment System

Payment must be separate from order creation and delivery.

Possible future integration:

- Payment processor
- Bank/payment account
- Payment gateway/API

The ideal system creates a unique payment reference for each transaction.

Example:

`ORDER-1045-83921`

When the payment provider confirms the payment through a webhook/API, update:

**Payment = Paid ✓**

Do not mark the order completed at this stage.

---

# 23. Logistics Section

This needs to be a major section of the app.

Use a clear logistics dashboard.

### Top tabs

**Overview | Requests | Active | Completed | Failed | Partners**

---

# 24. Logistics Overview

Show:

**Delivery Requests**
12

**Active Deliveries**
7

**Delivered Today**
31

**Failed**
2

Then show:

### Nearest / Available Logistics Partners

Example:

**Partner A**
Warri • Available
Estimated delivery: 45–60 min

**Partner B**
Warri • Available
Estimated delivery: 60–80 min

**Partner C**
Warri • Busy
Limited capacity

The interface should not force the business owner to manually search through every logistics organization.

---

# 25. Automatic Logistics Matching

When a delivery request is created, the system should use:

- Business location
- Customer delivery location
- Service coverage
- Partner availability
- Distance
- Delivery type
- Estimated price
- Partner capacity

The app can suggest:

**Recommended logistics partners**

The business owner can then:

**Send Request**

or choose another partner.

Future versions can allow automated partner assignment based on business rules.

---

# 26. Delivery Request Detail

Example:

**Delivery #DR-1045**

### Pickup
ABC Fashion Store

### Delivery
Customer address

### Package
- 2 × Black Shirt
- 1 × Blue Jeans
- Total order value: ₦55,000

### Assigned Partner

Partner A

### Rider

Michael

### Status

**In Transit**

Actions:

- Call rider
- View tracking
- View delivery details
- Cancel request (when allowed)

---

# 27. Logistics Partner Dashboard

A logistics organization gets a different dashboard from a business owner.

Main sections:

- New Requests
- Active Deliveries
- Riders
- Earnings / Partner reporting
- Completed
- Failed
- Profile

A logistics organization can see only deliveries assigned/requested to that organization.

---

# 28. Rider Flow

Rider sees:

### Today's Deliveries

Each card shows:

- Pickup
- Customer
- Delivery area
- Package count
- Amount/order reference
- Status

Actions:

**Accept**

**Picked Up**

**Start Delivery**

**Mark Delivered**

**Report Issue**

---

# 29. Delivery Confirmation

There should be two different delivery-confirmation flows.

## Logistics delivery

Preferred:

### Customer OTP

1. System generates OTP.
2. Customer receives OTP via supported communication channel.
3. Rider asks customer for the code.
4. Rider enters OTP.
5. Delivery is verified.
6. Delivery status becomes `Delivered`.
7. Transaction can become `Completed`.

Additional proof can include:

- Delivery photo
- Timestamp
- GPS/location record
- Customer signature

---

# 30. Personal Delivery

If the business owner delivers the product personally:

Button:

**Personally Delivered**

Confirmation options:

### Preferred
Customer OTP

### Alternative
Customer signature

### Alternative
Delivery photo

### Fallback
Manual confirmation

The app records:

- Person confirming delivery
- Date/time
- Location where available
- Optional note
- Optional proof photo

Then:

**Delivery = Delivered**

and, after the transaction requirements are satisfied:

**Completion = Completed**

---

# 31. Failed Delivery

A failed delivery should never simply disappear.

Reasons:

- Customer unavailable
- Wrong address
- Customer rejected order
- Rider issue
- Vehicle/transport issue
- Business issue
- Other

The rider/business owner can add a note.

The transaction remains visible with:

**Delivery: Failed**

The business owner can retry/reschedule.

---

# 32. Transaction History

Main navigation:

**Transactions**

Filters:

- All
- WhatsApp
- Manual
- Pending
- Paid
- Unpaid
- Awaiting Delivery
- In Transit
- Delivered
- Completed
- Failed
- Cancelled

Search:

- Customer
- Phone
- Transaction ID
- Product
- Date

Date filters:

- Today
- This week
- This month
- Custom range

---

# 33. Reports

The reporting section should show:

### Sales

- Total sales
- Number of orders
- Average order value

### Payments

- Paid
- Unpaid
- Failed
- Refunded

### Delivery

- Delivered
- Pending
- In transit
- Failed

### Products

- Top-selling products
- Quantity sold
- Revenue by product

### Sources

- WhatsApp sales
- Manual sales

Time filters:

- Today
- Week
- Month
- Custom range

---

# 34. Customer Records

The system should automatically build customer records from transactions and WhatsApp conversations.

Customer profile:

- Name
- Phone
- Total orders
- Total spent
- Last order
- Current orders
- Delivery history
- Notes

The business owner can open a customer and see the related transaction history.

---

# 35. Product Catalog

Business owners can create products:

- Product name
- Description
- Category
- Price
- SKU
- Stock quantity
- Image
- Active/inactive status

This makes manual transaction creation faster.

The AI can also use the product catalog when answering customers.

Example:

Customer:

> "How much is the black shirt?"

AI checks the catalog and responds with the current price.

---

# 36. Notifications

Notifications should cover:

- New WhatsApp order detected
- Payment confirmed
- Payment failed
- Delivery request accepted
- Rider assigned
- Pickup completed
- Delivery in transit
- Delivery completed
- Delivery failed
- Customer message needing human attention
- Low stock (future feature)

---

# 37. Profile / Settings

Sections:

### Business Profile
- Business information
- Address
- Category

### WhatsApp
- Connection
- AI settings
- Auto-reply settings

### Payments
- Connected payment provider
- Settlement/account details

### Logistics
- Preferred logistics providers
- Automatic matching
- Delivery preferences

### Notifications
- Push
- Email
- WhatsApp/SMS where supported

### Security
- Password
- PIN/biometric login
- Two-factor authentication

### Team
Future:
- Add staff
- Roles
- Permissions

---

# 38. Recommended Main Navigation

For the first version:

**Home**
- Business summary
- Quick actions
- Recent transactions

**Transactions**
- All transaction records
- Filters
- Transaction details

**AI / Chats**
- WhatsApp conversations
- AI status
- Order extraction
- Human takeover

**Logistics**
- Delivery requests
- Active deliveries
- Logistics partners
- Delivery history

**Profile**
- Business
- Products
- Payments
- WhatsApp
- Settings

---

# 39. Floating Quick Action

A central floating `+` action can provide:

- New Transaction
- Add Product
- Request Delivery
- Add Customer

The most important action should be:

**+ New Transaction**

---

# 40. Key User Journey — WhatsApp

**Customer sends WhatsApp message**

↓  
AI replies

↓  
AI identifies products

↓  
AI calculates/reads quantities and prices

↓  
Transaction draft created

↓  
Business confirms product availability

↓  
Payment requested

↓  
Payment confirmed

↓  
Delivery option selected

↓  
Logistics partner or business owner delivers

↓  
Delivery confirmed

↓  
Transaction completed

---

# 41. Key User Journey — Manual Sale

**Business owner taps + New Transaction**

↓

Adds customer

↓

Adds products and quantities

↓

Prices calculated

↓

Total calculated

↓

Confirms availability

↓

Customer pays

↓

Payment confirmed

↓

Delivery requested or owner chooses personal delivery

↓

Delivery confirmed

↓

Transaction completed

---

# 42. Important Business Rule

The app must preserve the distinction between:

**Order created**

**Payment received**

**Product delivered**

**Transaction completed**

Never assume that payment means the transaction is complete.

Example:

> Order: Confirmed  
> Payment: Paid  
> Delivery: Pending  
> Completion: Open

This is one of the most important rules in the product.

---

# 43. Home Dashboard Example

A polished first version of the home screen can follow this hierarchy:

### Header
Business avatar + greeting + notifications + WhatsApp connection

### Main card
**Business Sales**
₦XXX,XXX
This month

### Quick Actions
- New Transaction
- Transactions
- AI / WhatsApp
- Logistics
- Products
- Payments
- Customers
- Reports

### Status row
- Pending Payment
- Awaiting Delivery
- In Transit
- Completed

### Recent Transactions
Transaction list + See all

### Bottom Navigation
Home | Transactions | AI/Chats | Logistics | Profile

---

# 44. UI Components

Use consistently:

- Rounded cards
- Rounded inputs
- Soft shadows
- Clear dividers
- Status pills
- Compact line icons
- Large numeric summaries
- Bottom sheets for quick actions
- Confirmation dialogs for sensitive operations
- Skeleton loading states
- Empty states
- Toast/snackbar notifications

---

# 45. Responsive App Behavior

This project is an **app-first product**, not a web app.

The interface should be optimized for phone use.

Important behaviors:

- Smooth transitions between tabs
- Bottom navigation remains stable
- Swipeable cards where useful
- Pull-to-refresh for live status lists
- Bottom sheets for secondary actions
- Search available in long lists
- Forms broken into manageable sections
- Avoid overly dense desktop-style tables

---

# 46. Suggested Screen List

## Authentication
1. Splash
2. Login
3. Create Account
4. Account Type
5. Business Onboarding
6. Logistics Onboarding
7. Rider Onboarding
8. Verify Phone/Email
9. Forgot Password

## Business
10. Home
11. Notifications
12. Transactions
13. Transaction Detail
14. Create Transaction
15. Edit Transaction
16. Products
17. Product Detail
18. Customers
19. Customer Detail
20. Reports
21. Payments

## WhatsApp AI
22. AI Inbox
23. Chat Detail
24. AI Order Preview
25. AI Settings
26. Human Takeover Mode

## Logistics
27. Logistics Overview
28. Delivery Requests
29. Delivery Detail
30. Partner List
31. Partner Detail
32. Active Delivery
33. Delivery Tracking
34. Delivery Confirmation
35. Failed Delivery
36. Personal Delivery Confirmation

## Logistics Partner
37. Organization Dashboard
38. Requests
39. Delivery Details
40. Riders
41. Rider Detail
42. Completed Deliveries
43. Failed Deliveries

## Profile / Settings
44. Business Profile
45. WhatsApp Settings
46. Payment Settings
47. Logistics Preferences
48. Notifications
49. Security
50. Team / Permissions

---

# 47. MVP Priority

## Phase 1 — Core

Build first:

- Authentication
- Business onboarding
- Home dashboard
- Manual transaction
- Product catalog
- Transaction history
- Payment status
- Personal delivery confirmation
- Basic logistics request
- Logistics partner account
- Rider delivery flow

## Phase 2 — WhatsApp AI

- WhatsApp connection
- AI replies
- Conversation management
- Order extraction
- AI transaction drafts
- Human takeover

## Phase 3 — Payments & Logistics Automation

- Payment provider integration
- Payment webhooks
- Automatic matching of logistics partners
- Partner availability
- Rider assignment
- Delivery OTP
- Proof of delivery

## Phase 4 — Growth

- Advanced reports
- Inventory
- Team accounts
- Automated customer follow-ups
- Advanced AI
- Multiple payment providers
- More logistics partners
- Multi-city expansion

---

# 48. Product Principle

The app should always answer four questions for the business owner:

### What did the customer order?
**Order**

### Has the customer paid?
**Payment**

### Has the customer received the product?
**Delivery**

### Is the transaction finished?
**Completion**

That clarity should be the foundation of the entire UI.

---

# 49. Final Product Structure

The app can be summarized as five connected systems:

**1. Business Management**
→ products, customers, transactions, reports

**2. WhatsApp AI**
→ conversations, automatic responses, order extraction

**3. Payments**
→ payment tracking and future payment-provider integration

**4. Logistics Network**
→ multiple logistics companies, riders, delivery requests and tracking

**5. Delivery Confirmation**
→ logistics confirmation or direct/manual confirmation

Together:

**WhatsApp / Manual Sale**
→ **Transaction**
→ **Payment**
→ **Delivery**
→ **Confirmation**
→ **Completed Business Record**

