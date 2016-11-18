namespace Jfi.TestAzureProject.WebRole.Tests
{
    using Microsoft.VisualStudio.TestTools.UnitTesting;

    using Controllers;

    [TestClass]
    public class HomeControllerTests
    {
        [TestMethod]
        public void Add_AddsTwoNumbers()
        {
            var controller = new HomeController();

            Assert.AreEqual(4, controller.AddNumbers(1, 3));
        }
    }
}
