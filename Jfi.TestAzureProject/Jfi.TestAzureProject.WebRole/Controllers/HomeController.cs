using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Jfi.TestAzureProject.WebRole.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.DisplayMessage = "TEST MESSAGE UPDATED ON GIT";

            ViewBag.GeneratedNumber = AddNumbers(5, 5).ToString();

            return View();
        }

        public ActionResult About()
        {
            ViewBag.Message = "Your application description page.";

            return View();
        }

        public ActionResult Contact()
        {
            ViewBag.Message = "Your contact page.";

            return View();
        }

        public int AddNumbers(int first, int second)
        {
            return first + second;
        }
    }
}
