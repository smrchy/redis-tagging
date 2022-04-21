# Migration from v1.x to v2.x

> In v2.x support for callbacks was dropped and everything is now promise based.\
> The functions can be used with `.then()`/`.catch()` or async/await.\
> Function signatures (except for callbacks) and returns have not changed.

## Migrate

From:

```javascript
var RedisTagging = require("redis-tagging");
var rt = new RedisTagging({host: "127.0.0.1", port: 6379, nsprefix: "rt"} );

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

### Usage with async/await

```javascript
import RedisTagging from "redis-tagging";
const rt = new RedisTagging({host: "127.0.0.1", port: 6379, nsprefix: "rt"});

(async () =>{
    try {
        const resp = await rt.set({
            bucket: "concerts",
            id: "itm123",
            tags: ["new york", "stadium", "rock", "open-air"],
            score: 1356341337
        })
        // resp === true - this is always the case if no error was thrown
        // item was saved
    } catch (err){
        // catch errors here - e.g. invalid options or redis errors
    }
})();
```

### Usage with `.then()`/`.catch()`

```javascript
import RedisTagging from "redis-tagging";
const rt = new RedisTagging({host: "127.0.0.1", port: 6379, nsprefix: "rt"});

rt.connect().then(() => {
    rt.set({
        bucket: "concerts",
        id: "itm123",
        tags: ["new york", "stadium", "rock", "open-air"],
        score: 1356341337
    })
    .then((resp) => {
        // resp === true - this is always the case if no error was thrown
        // item was saved
    })
    .catch((err) => {
        // catch errors here - e.g. invalid options or redis errors
    });
});
```
