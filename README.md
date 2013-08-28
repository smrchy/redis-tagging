# Redis-Tagging

[![Build Status](https://secure.travis-ci.org/smrchy/redis-tagging.png?branch=master)](http://travis-ci.org/smrchy/redis-tagging)

Fast and simple tagging of (sorted) items.

## Features

- **Maintains the order of tagged items** with the help of **Redis Sorted Sets**.
- **Unions** and **intersections** on tags while also maintaining the order.
- **Fast and efficient paging** over thousands of results with support of `limit`, `offset`.
- Namespaces to keep multiple "buckets" of tags on the same server.
- Counters for each tag in a namespace. 
- REST interface via [REST Tagging](https://github.com/smrchy/rest-tagging)
- [Test coverage](http://travis-ci.org/smrchy/redis-tagging)

## A short example

Tagging and efficient querying of items with unions and intersections is no fun with traditional databases.

Imagine a SQL database with concerts that need to be output ordered by date. Each item is tagged with tags like `chicago`, `rock`, `stadium`, `open-air`. Now let's try to get the following items:

- 10 concerts (orderd by date) in `chicago` (limit=10, tags=["chicago"]) and the total amount of concerts in `chicago`.
- The next 10 concerts, skipping the first 10,  (limit=10, tags=["chicago"], offset=10) and the total amount.
- 40 concerts in `detroit`, `chicago` or `cleveland` (limit=40, tags=["detroit", "chicago", "cleveland"], type="union") and the total amount.
- 50 concerts that are `rock` and in a `stadium` (limit=50, tags=["rock", "stadium"]) and the total amount.
- The top 20 tags used and the amount of items tagged with each.

Those queries together with the maintenance of tables and indexes can be a pain with SQL. Enter Redis and its fast in-memory set opererations.

### Fast and efficient tagging

Here is how Redis-Tagging will make the tagging of items in external databases fast and easy:

- When storing an item in your database you still store the tags but in a normal string field for reference and easy output. **You will no longer use this field in a WHERE-statement**. No additional tables for tags and tag associations are needed.
- You post the `id`, a `score` (for sorting) and the list of `tags` to Redis-Tagging whenever you add, update or delete an item. The *score* could be a date timestamp or any other number you use for sorting.
- Redis-Tagging will output all results (e.g. all items with tags `chicago` and `rock`) as a list of IDs *ordered correctly* by the score you supplied.
- You use this list of IDs to get the actual items from your database.

So with little changes you will end up with a lot less code, tables and need to maintain a complex structure just to support fast tagging.


## Installation

`npm install redis-tagging`

## Usage

**Note:** If you want to use the REST interface to access Redis Tagging from a non NodeJS application please have a look at: [REST Tagging](https://github.com/smrchy/rest-tagging)

```javascript
var RedisTagging = require("redis-tagging");
var rt = new RedisTagging();
```

**Important:** Redis-Tagging works with items from your database (whatever you might use). Its purpose is to make tag based lookups fast and easy.  
A typical item in your database should include an id (the primary key) and a list of tags for this items. You could store this as a JSON string (e.g. `["car", "bmw", "suv", "x5"]`.  
You'll want to try to keep your db in sync with the item ids stored in Redis-Tagging.

Go through the following examples to see what Redis-Tagging can do for you: 

### Set tags for an item

This will create an item with the id `itm123`.  
Note: There is no partial update of tags for an item. You always write the full list of tags.

```javascript
rt.set(
	{
		bucket: "concerts",
		id: "itm123",
		tags: ["new york", "stadium", "rock", "open-air"],
		score: 1356341337
	},
	function (err, resp) {
		if (resp === true) {
			// item was saved
		}
	}
);
```

### Get tags for an item

Returns all tags for an item id.

Note: This method is usually not needed if you store the tags for each item in your database.

```javascript
rt.get(
	{
		bucket: "concerts",
		id: "itm123"
	},
	function (err, resp) {
		// resp countains an array of all tags
		// For the above set example resp will contain:
		// ["new york", "stadium", "rock", "open-air"]
	}
);
```

### Remove all tags for an item

Note: This is the same as using `set` with an empty array of tags.

```javascript
r.remove(
	{
		bucket: "concerts",
		id: "itm123"
	},
	function (err, resp) {
		if (resp === true) {
			// item was removed
		}
	}
);
```

### Get all item ids in a bucket

```javascript
r.allids(
	{
		bucket: "concerts"
	}
	,
	function (err, resp) {
		// resp countains an array of all ids
	}
);
```

### Tags: Query items by tag

The main method. Return the IDs for one or more tags. When more than one tag is supplied the query can be an intersection (default) or a union.
`type=inter` (default) only those IDs will be returned where all tags match. 
`type=union` all IDs where any tag matches will be returned.

Parameters object:

* `bucket` (String)
* `tags` (Array) One or more tags
* `limit` (Number) *optional* Default=100 (0 will return 0 items but will return the total_items!)
* `offset` (Number) *optional* Default=0
* `withscores` (Number) *optional* Default=0 Set this to 1 to output the scores
* `order` (String) *optional* Default ="desc"
* `type` (String) *optional* "inter", "union" Default: "inter"

```javascript
rt.tags(
	{
		bucket: "concerts",
		tags: ["berlin", "rock"],
		limit: 2,
		offset: 4
	},
	function (err, resp) {
		// resp contains:
		// 	{"total_items":108,
		//  "items":["8167","25652"],
		//  "limit":2,
		//  "offset":4}
	}
);
```
The returned data is item no. 5 and 6. The first 4 got skipped (offset=4). You can now do a

`SELECT * FROM Concerts WHERE ID IN (8167,25652) ORDER BY Timestamp DESC`


### Top Tags

Return the top *n* tags of a bucket.

```javascript
rt.toptags(
{
		bucket: "concerts",
		amount: 3
	},
	function (err, resp) {
		// resp contains:
		// 	{
		//		"total_items": 18374,
		//	 	"items":[
		//			{"tag":"rock", "count":1720},
		//			{"tag":"pop", "count":1585},
		//			{"tag":"New York", "count":720}
		//		]
		//	}
	}
);
```

### Buckets

List all buckets with at least one item stored in Redis.

Important: This method uses the Redis `keys` command. Use with care.

```javascript
rt.buckets(
	function (err, resp) {
		// resp contains an array with all buckets
	}
);
```

### Remove a bucket

Removes a single bucket and all items

```javascript
rt.removebucket(
	{
		bucket: "concerts"
	},
	function (err, resp) {
		if (resp === true) {
			// bucket was removed
		}
	}
);
```

## How to migrate to Redis-Tagging

- Make sure your DB has the following fields for the items you want to tag (names don't need to match exactly):
	- `id`: A primary key to quickly find your item.
	- `score`: Any number you use to sort your data. This is usually a date. If you saved a date in date-format you need to convert it to a numeric timestamp.
	- `tags`: A list of tags for this item. It is up to you how you store this. Usually a normal string field is sufficient.
- Do a `set` for each item to populate the Redis-Tagging data.
- When you insert / update / delete items in your DB make sure you also tell Redis-Tagging about it.
- Now use the methods described above to make intersections and get the IDs back.
- Use the IDs to get the actual records from your DB and display them as usual.
- Enjoy.


## License 

(The MIT License)

Copyright (c) 2010 TCS &lt;dev (at) tcs.de&gt;

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.