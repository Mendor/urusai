# -*- coding: utf-8 -*-

import urusai_plugin
import os
import re
import pickle
import random


FILE = "var/quotes_{0}.dat"


# If file not present, create it and all its parent directories and return its descriptor
def checkFile(f):
    try:
        with open(f):
            pass
    except IOError:
        d = os.path.dirname(f)
        if not os.path.exists(d):
            os.makedirs(d)
        open(f, 'w').close()

# Unserialize data from file
def read_file(muc):
    qfile = FILE.format(muc)
    checkFile(qfile)
    with open(qfile, 'rb') as f:
        try:
            return [item.decode('string_escape') for item in pickle.load(f)]
        except EOFError:
            return []

# Serialize data to file
def write_file(muc, lines):
    qfile = FILE.format(muc)
    with open(qfile, 'wb') as f:
        pickle.dump(lines, f)
    pass


class pluginQuote(urusai_plugin.MucMessage):
    """
    Chat quotes.
    Usage:
        "aq <QUOTE TEXT>" — add quote
        "q" — get random quote
        "q 42" — get the quote number 42
        "q lol" — get the first quote containing 'lol' text
        "dq 13" — delete the quote number 13
    """

    triggers = {
        "^aq\s.+" : "Add",
        "^q(\s.+)?" : "Get",
        "^dq\s[0-9]+" : "Del"
    }

    @staticmethod
    def triggerAdd(fromName, fromJid, message):
        [muc, author] = fromName.split("/", 1)
        q_fmt = "{0}~%~{1}"
        reply_fmt = "Quote added (number {0})"
        r = re.compile(r"^aq\s(.+)", flags=re.MULTILINE|re.DOTALL)
        quote = re.match(r, message).group(1).encode('string_escape')
        lines = read_file(muc)
        lines.append(q_fmt.format(quote, author))
        number = len(lines)
        write_file(muc, lines)
        return reply_fmt.format(number)

    @staticmethod
    def triggerGet(fromName, fromJid, message):
        reply_fmt = "[{0}/{1}] (added by {2})\n{3}"
        request = re.match(r"^q(\s(.+))?", message).group(2)
        [muc, author] = fromName.split("/", 1)
        lines = read_file(muc)
        if not lines:
            return "No quotes added for this MUC."
        count = len(lines)
        if not request:
            i = random.randint(0, count - 1)
            [quote, added] = lines[i].split("~%~", 1)
            return reply_fmt.format(i + 1, count, added, quote)
        if request.isdigit():
            if int(request) <= 0:
                return "Quote not found."
            try:
                line = lines[int(request) - 1]
            except IndexError:
                return "Quote not found."
            [quote, added] = line.split("~%~", 1)
            return reply_fmt.format(request, count, added, quote)
        else:
            for i in range(0, count - 1):
                if request in lines[i]:
                    [quote, added] = lines[i].split("~%~", 1)
                    return reply_fmt.format(i, count, added, quote)
            return "Quote not found."

    @staticmethod
    def triggerDel(fromName, fromJid, message):
        reply_fmt = "Quote {0} deleted."
        request = int(re.match(r"^dq\s([0-9]+)?", message).group(1))
        [muc, author] = fromName.split("/", 1)
        lines = read_file(muc)
        if not lines:
            return "No quotes added for this MUC."
        if request <= 0 or request > len(lines):
            return "Quote not found."
        del lines[request - 1]
        write_file(muc, lines)
        return reply_fmt.format(request)
