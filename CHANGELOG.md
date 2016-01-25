# CHANGELOG

## 1.4.0

* Travis tests for Node.js 4.2
* Upgraded to lodash 4.x
* Loading only needed lodash modules

## 1.3.0

* Travis tests for Node.js 4.1 and 5.0
* Removed Travis tests for 0.8.x and iojs
* Node.js 0.8.x is no longer supported

## 1.2.2

* Fix: For incorrect handling of `limit:0` with `tags` method
* Test-Support for Node.js 0.12 and iojs
* Minor doc changes
* Added: LICENSE.md file

## 1.2.1

* Switched from Underscore to LoDash
* Don't issue empty multi statements in special cases (issue #2)

## 1.1.5

* Make `hiredis` optional.

## 1.1.4

* Added support for [https://github.com/mranney/node_redis#rediscreateclientport-host-options](redis.createClient) `options` object.
* Added docs for `client` option to supply an already connected Redis object to **redis-tagging*.