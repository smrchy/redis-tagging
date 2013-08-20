# Redis Data Structure

## rt:{bucket}:ID:{id} *SET*

This set contains all tags (as members) for an item

## rt:{bucket}:TAGCOUNT *SORTED SET*

This sorted set contains all tags (as members) for a bucket with score being the counter for the number of items that have this tag.

## rt:{bucket}:TAGS:{tag} *SORTED SET*

This sorted set contains all item ids (as members) for a single tag with score being the supplied score of that item (for example a timestamp).

## rt:{bucket}:IDS *SET*



