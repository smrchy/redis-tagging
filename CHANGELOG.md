# CHANGELOG

## 1.2.1

* Switched from Underscore to LoDash
* Don't issue empty multi statements in special cases (issue #2)

## 1.1.5

* Make `hiredis` optional.

## 1.1.4

* Added support for [https://github.com/mranney/node_redis#rediscreateclientport-host-options](redis.createClient) `options` object.
* Added docs for `client` option to supply an already connected Redis object to **redis-tagging*.