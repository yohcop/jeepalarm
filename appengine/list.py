import os

from google.appengine.ext import webapp
from google.appengine.ext.webapp.util import run_wsgi_app
from google.appengine.ext.webapp import template

from models import Reccord

class MainPage(webapp.RequestHandler):
  def get(self):
    q = Reccord.all().order("-ts")

    results = q.fetch(50)
    for r in results:
      r.parse()

    template_values = {
      "reccords": results
    }

    path = os.path.join(os.path.dirname(__file__), 'list.html')
    self.response.out.write(template.render(path, template_values))

application = webapp.WSGIApplication([('/', MainPage)],
                                     debug=True)

def main():
  run_wsgi_app(application)

if __name__ == "__main__":
  main()
