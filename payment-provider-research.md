# Card provider availability notes

Research checked on 13 October 2026. The managed GoRide SA Stripe integration attempt returned `country_not_supported`; card checkout is therefore kept inactive while the user selects a workable gateway.

Stripe’s global availability page lists South Africa under “Extended network” and links to Paystack’s South Africa page. Paystack describes itself as a Stripe subsidiary focused on African commerce and says South African businesses can accept local and international payments. [Stripe availability](https://stripe.com/global) · [Paystack in South Africa](https://paystack.com/stripe/south-africa)

Paystack publishes official API documentation for collecting transactions and offers card payment channels. Any Paystack implementation still requires the user’s account and test credentials, a server-created transaction, verified webhook processing and persisted payment records. [Paystack payments](https://paystack.com/docs/payments/) · [Paystack API](https://paystack.com/docs/api/)

PayFast’s official developer guide documents custom hosted checkout, live and sandbox endpoints, credit-card (`cc`) and debit-card (`dc`) methods, and security checks for its Instant Transaction Notifications. It requires merchant credentials and a correctly verified notification before updating payment status. [PayFast developer documentation](https://developers.payfast.co.za/)

The project should retain a provider-neutral card adapter until the user selects Paystack, PayFast or an eligible Stripe account. Never claim card payments are live without configured credentials and a tested payment notification path.
