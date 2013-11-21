Urusai 0.0.1
============

Jabber (XMPP) bot with extendability using Python plugins.


Software requirements
---------------------

  * **Erlang R16B** or newer
  * **Rebar** in any directory from ``$PATH`` for building (it's compiled binary is provided with this repo)
  * **Python 2.7.x**


External dependencies
---------------------

  * [exmpp](https://github.com/processone/exmpp)
  * [erlport](https://github.com/hdima/erlport)
  * [pooler](https://github.com/seth/pooler)
  * [lager](https://github.com/basho/lager)


Installation
------------

```
git clone https://github.com/Mendor/urusai.git
cd urusai
make deps
make
```


Configuration
-------------

Configuration example can be found in ``default.config.sample``. You may edit this file and rename it to ``default.config`` later or create new configuration file based on this one. [Look inside it](https://github.com/Mendor/urusai/blob/master/default.config.sample) for configuration details.


Running
-------

    ./start.sh default

Where ``default`` is the base name for your configuration (``default.config`` in this case).


Bot management
--------------

Send to the bot subscription from JID set as owner in configuration file. Then you may manage using the following commands:

  * ``ping`` — pong!
  * ``status <YOUR_STATUS_MESSAGE>`` — update status message
  * ``owner list`` — list of bot's owners
  * ``owner add <JID>`` — add <JID> to owners list
  * ``owner del <JID>`` — remove <JID> from owners list (warning: all the owners have the same rights, but the main owner cannot be deleted from the list)
  * ``muc join <MUC_ADDRESS>`` — join MUC
  * ``muc leave <MUC_ADDRESS>`` — leave MUC
  * ``muc nick <MUC_ADDRESS>`` — change bot's shown nick for this MUC
  * ``plugins`` — list of loaded plugins' triggers information
  * ``plugins reload`` — reload plugins
  * ``exec <COMMAND>`` — execute private message plugin command


Plugin API
----------

All the plugins are stored in modules with ``.py`` or ``.pyc`` extension under ``plugins`` directory.

Example of plugin module source code:

```python
import urusai_plugin # required for plugin correct work
from datetime import datetime

# Plugin class name should start from 'plugin' and be inherited from
# 'urusai_plugin.Private' class for working with messages sent to
# the bot directly.
class pluginTime(urusai_plugin.Private):
    """
    This plugin class implements replying current time for any user
    sent 'time' string to bot.
    """
    # 'triggers' dict as class property is strongly required.
    # Every key in dict is regular expression (without 'r' prefix!)
    # used for plugin action triggering, and every value is the name
    # of method running when key regexp triggered.
    triggers = { "^time": "Time" }

    # Trigger method name should start from 'trigger' and being
    # preceded by '@staticmethod' decorator.
    # Trigger method should has three parameters:
    #   1st — JID or conference JID/nickname of message sender
    #   2nd — real JID of sender (used only for MUC plugins)
    #         (not implemented yet)
    #   3rd — origin message body
    # Method should return string with the message which will be
    # send back to the user or MUC.
    @staticmethod
    def triggerTime(fromName, fromJid, message):
        return str(datetime.now())

# Inheritance from 'urusai_plugin.MucMessage' is used for plugins
# that may be triggered from MUC chats. All other information about
# 'triggers' property and writing methods is the same.
class pluginTimeChat(urusai_plugin.MucMessage):
    triggers = { "^time": "Time" }

    @staticmethod
    def triggerTime(fromName, fromJid, message):
        return str(datetime.now())

```

All other classes and methods inside modules are not parsed and may be used for coding convenience.

More plugin examples are available under [``plugins`` directory](https://github.com/Mendor/urusai/tree/master/plugins) of this repo.


TODO
----

  * SSL!
  * HTTP API
  * MUC autorejoin
  * passing real JIDs from conferences to plugins
  * MUC presence plugins API
  * IQ handler
  * more features for plugin returning values


License
-------

[WTFPL](http://www.wtfpl.net/)
