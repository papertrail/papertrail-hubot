## Hubot scripts from Papertrail

A collection of Hubot scripts from your friendly folks at Papertrail.

Includes support for:

- [Papertrail](https://papertrailapp.com/). Run "help papertrail" for a list of commands

### Installation

Add the repository to your hubot's package.json:

```
dependencies: {
  "papertrail-hubot": "git://github.com/papertrail/papertrail-hubot.git"
}
```

Include the package in your hubot's external-scripts.json

```
["papertrail-hubot"]
```

### Usage

Basic querying with "log me" or "papertrail me"

```
hubot log me 127.0.0.1
hubot papertrail me 127.0.0.1
```

Limit to a group:

```
hubot log me group=redis -"saved on disk"
```

Limit to a host:

```
hubot log me host=worker1
```


### TODO

- create list

### License

See LICENSE file.

Copyright (c) 2014 Papertrail Inc.
