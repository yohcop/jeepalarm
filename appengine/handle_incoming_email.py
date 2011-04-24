import datetime, logging, email
from google.appengine.ext import webapp
from google.appengine.ext.webapp.mail_handlers import InboundMailHandler
from google.appengine.ext.webapp.util import run_wsgi_app

from models import Reccord

class LogSenderHandler(InboundMailHandler):
  def receive(self, message):
    logging.info("Received a message from: " + message.sender)

    for content_type, body in message.bodies('text/plain'):
      dec = body.decode()
      rec = Reccord(raw=dec)
      rec.put()
      return


application = webapp.WSGIApplication(
    [LogSenderHandler.mapping()], debug=True)

def main():
  run_wsgi_app(application)

if __name__ == "__main__":
  main()
