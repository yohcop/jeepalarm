import datetime
from google.appengine.ext import db

class Reccord(db.Model):
  ts = db.DateTimeProperty(auto_now_add=True)
  raw = db.TextProperty()

  # Parse the raw property, and create attributes from the content.
  # e.g. if raw contains Pos:xxxx Foo:yyyy
  #      this function will create attribute Pos with value xxxx
  #      and attribute Foo with value yyyy.
  # Note: this is absolutely not safe and may override other attribute values
  # but since we never modify the reccords, it's fine for now, and makes it
  # easy to use in templates, etc.
  def parse(self):
    if hasattr(self, 'parsed'):
      return
    for part in self.raw.split():
      keyval = part.split(':', 1)
      if len(keyval) == 2:
        setattr(self, keyval[0], keyval[1])
    self.parsed = True

