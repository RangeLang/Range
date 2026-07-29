# RangeStore

RangeStore is the first Range-authored durable document-storage slice. It is
not a PocketBase replacement yet: it provides the persistence core that a
collection schema, query indexes, auth, realtime subscriptions, and an HTTP
surface can build on.

The store uses two layers:

- an atomic metadata revision log at the caller-supplied path; and
- one immutable body sidecar per successful document revision.

Metadata records have the form:

```text
documentID:revision:deleted:bodyLength
```

The public Range surface currently provides:

- `documentStorePut(path:id:body:)`, returning the committed revision or a
  negative host error;
- `documentStoreRemove(path:id:)`, recording a tombstone and returning its
  revision or a negative host error;
- `documentStoreGet(source:id:)`, folding one immutable metadata snapshot to
  the latest revision; and
- `StoredDocument`, containing presence, stable integer identity, revision,
  and body length.

The caller loads the metadata snapshot with `readFile(path:)`. A present
document body is stored at:

```text
<path>.document.<documentID>.<revision>
```

This explicit snapshot boundary is intentional. The accepted compiler can
prove the pure Range query and primitive result today, while a stateful store
handle that returns owned dynamic strings remains blocked by the current owned
aggregate-return proof.

Run the supported proof with:

```sh
scripts/range check-document-store
```
