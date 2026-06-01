# Abserde

Abserde is a schematized datastore library that uses [Pack](https://github.com/isoopod/Pack) to create schematized keys.
As a result, Abserde stores data more efficiently than traditional libraries and gives you fine-grained control of your
data as the schemas evolve over time.

Abserde introduces a profile-centric architecture. Instead of forcing you to manage and open a single datastore key at a time,
Abserde allows you to design comprehensive profiles that aggregate multiple datastore keys into a single, unified player profile.
When a player joins, you simply open their profile, and the library handles the underlying multi-key orchestration seamlessly.
Aggregation not only keeps your data highly organized and modularized as features expand, but it also minimizes boilerplate code
typically required to fetch and sync fragmented player data across traditional single-key systems.

Documentation work in progress
