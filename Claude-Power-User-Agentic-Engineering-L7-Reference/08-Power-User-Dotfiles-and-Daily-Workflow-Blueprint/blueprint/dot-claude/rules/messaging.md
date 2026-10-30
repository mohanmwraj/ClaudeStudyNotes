---
paths:
  - "**/adapter/out/messaging/**"
  - "**/adapter/in/messaging/**"
---
# Messaging rules
- Publish only through the transactional outbox; the event id is created when the outbox row is written.
- The record key is the aggregate id.
- Consumers insert (consumer_group, event_id) into processed_events and apply the effect in one transaction, then acknowledge.
- Retries are bounded with exponential back-off; deserialization and validation errors go straight to the DLT.
- Copy the traceparent header from the outbox row to the record.
