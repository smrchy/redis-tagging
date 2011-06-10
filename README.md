# redis-tagging

## A fast and simple tagging library.

Based on [Redis](http://redis.io/) and [NodeJS](http://nodejs.org).
Useful for easy tagging of (sorted) items in external databases like mySQL.

### Features

- **Maintains the order of tagged items** with the help of [**Redis Sorted Sets**](http://redis.io/commands#sorted_set).
- **Unions** and **intersections** on tags while also maintaining the order.
- Fast and efficient paging over results with support of **limit**, **offset**.
- Namespaces to keep multiple "buckets" of tags on the same server.
- Counters for each tag in a namespace. 

#### Comes in two flavors

- **RESTful** (to use from PHP, ASP, Coldfusion etc. where you can't install Redis and or NodeJS)
- **Javascript** version for use from within NodeJS.

### The story

Tagging and efficient querying of items with unions and intersections is no fun with traditional databases.

Example: A SQL database with concerts ordered by date and each item is tagged with tags like `chicago`, `rock`, `stadium`, `open-air`. Now let's try to get the following items:

- 10 concerts (orderd by date) in `chicago` (limit=10, tags=["chicago"]) and the total amount of concerts in `chicago`.
- The next 10 concerts, skipping the first 10,  (limit=10, tags=["chicago"], offset=10) and the total amount.
- 40 concerts in `detroit`, `chicago` or `cleveland` (limit=40, tags=["detroit", "chicago", "cleveland"], type="union") and the total amount.
- 50 concerts that are `rock` and in a `stadium` (limit=50, tags=["rock", "stadium"]) and the total amount.
- The top 20 tags used and the amount of items tagged with each.

Those queries together with the maintenance of tables and indexes can be a pain with SQL. Enter Redis and its fast in-memory set opererations.

### Redis-Tagging

Here is how `redis-tagging` will make the tagging of items in external databases fast and easy:

- When storing an item in SQL you still store the tags but in a normal string field for reference and easy output. **You will no longer use this field in a WHERE-statement**. No additional tables for tags and tag associations are needed.
- You post the `id`, a `score` (for sorting) and the list of `tags` to `redis-tagging` whenever you add, update or delete an item. The *score* could be a date timestamp or any other number you use for sorting.
- As `redis-tagging` stores only IDs, score and tags the result of a query (e.g. all items with tags `chicago` and `rock`) is a list of IDs *but ordered correctly* by the score you supplied.
- You use this list of IDs that are returned from `redis-tagging` to grab the actual items from your database.

## Installation

### REST Interface to use *redis-tagger* from external applications (PHP, ASP etc.):

	node server_multi.js

then use HTTP (see **REST Interface** below).

### Or use it from within NodeJS:
	
	...
	var	NAMESPACE_PREFIX = "tgs:",
		redisclient = require("redis"),
		redis = redisclient.createClient(),
		RedisTagging = require("./redis-tagging").multi_namespace,
		rt = new RedisTagging(redis, NAMESPACE_PREFIX);

		rt.toptags("concerts", 30, function (reply) {...});
 	...
 	Have a look at redis-tagging.coffee for all supported commands.

## REST Interface:
	
- POST */tagger/id/:namespace/:id*

	Add or update an item. The URL contains the namespace (e.g. 'concerts') and the id for this item.

	Example: `POST /tagger/id/concerts/571fc1ba4d`

	Required form-fields:

	- score (Number) This is the sorting criteria for this item
	- tags (String) A JSON string with an array of one or more tags (e.g. ["chicago","rock"])

	Returns: `{"ok":true}`

- DELETE */tagger/id/:namespace/:id*

	Delete an item and all its tag associations.

	Example: `DELETE /tagger/id/concerts/12345`

	Returns: `{"ok":true}`

- GET */tagger/tags/:namespace?queryparams*

	The main method. Return the IDs for one or more tags. When more than one tag is supplied the query can be an intersection (default) or a union.
	`type=inter` (default) only those IDs will be returned where all tags match. 
	`type=union` all IDs where any tag matches will be returned.

	Parameters:

	- `tags` (String) a JSON string of one or more tags.
	- `type` (String) *optional* Either **inter** (default) or **union**.
	- `limit` (Number) *optional* default: 100.
	- `offset` (Number) *optional* default: 0 The amount of items to skip. Useful for paging thru items.
	- `withscores` (Number) *optional* default: 0 Set this to 1 to also return the scores for each item.
	- `order` (String) *optional* Either **asc** or **desc** (default).

	Example: `/tagger/tags/concerts?tags=["Berlin","rock"]&limit=2&offset=4&type=inter`

	Returns: 

		{"total_rows":108,
		 "rows":["8167","25652"],
		 "limit":2,
		 "offset":4}

	The returned data is item no. 5 and 6. The first 4 got skipped (offset=4). You can now do a

	`SELECT * FROM Concerts WHERE ID IN (8167,25652) ORDER BY Timestamp DESC`

	Important: `redis-tagging` uses Redis Sorted Sets. This is why the order of the items that you supplied with the `score` parameter is maintained. This way you can page thru large result sets without doing huge SQL queries.

	Idea: You might consider to use a reverse proxy on this URL so clients can access this data via AJAX. JSONP via standard `callback` URL parameter is supported.

- GET */tagger/toptags/:namespace/:amount*

	Get the top *n* tags for a namespace.

	Example: `GET /tagger/toptags/concerts/3`

	Returns:

		{"total_rows": 18374,
		 "rows":[
			{"tag":"rock", "count":1720},
			{"tag":"pop", "count":1585},
			{"tag":"New York", "count":720}
		]}

- GET */tagger/id/:namespace/:id*

	Get all associated tags for an item. Usually this operation is not needed as you will want to store all tags for an item in you database.

	Example: `GET /tagger/id/concerts/12345`

- GET */tagger/allids/:namespace*

	Get all IDs saved for a namespace. This is a costly operation that you should only use for scheduled cleanup routines.

	Example: `GET /tagger/allids/concerts`

## Javascript version

see *redis-tagging.coffee* for details.

## How to migrate to redis-tagging

- Make sure your DB has the following fields for the items you want to tag (names don't need to match exactly):
	- `id`: A primary key to quickly find your item.
	- `score`: Any number you use to sort your data. This is usually a date. If you saved a date in date-format you need to convert it to a numeric timestamp.
	- `tags`: A list of tags for this item. It is up to you how you store this. Usually a normal string field is sufficient. When you supply them to `redis-tagging` you supply a JSON array.
- Do a POST / SET for each item to populate the `redis-tagging` data.
- When you insert / update / delete items in your DB make sure you also tell `redis-tagging` about it.
- Now use the methods described above to make intersections and get the IDs back.
- Use the IDs to get the actual records from your DB and display them as usual.
- Enjoy.

## Using redis-tagger with a single namespace

To use `redis-tagger` in NodeJS with just one single namespace:

	var	NAMESPACE_PREFIX = "tgs:",
		redisclient = require("redis"),
		redis = redisclient.createClient(),
		RedisTagging = require("./redis-tagging").single_namespace,
		rt = new RedisTagging(redis, NAMESPACE_PREFIX, "concerts");

		rt.toptags(30, function (reply) {...});



## Work in progress

`redis-tagging` is work in progress. Your ideas, suggestions etc. are very welcome.

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