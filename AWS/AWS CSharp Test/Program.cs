using System;
using System.Text;
using System.Net;
using System.Windows.Forms;
using System.Web;
using System.Collections.Specialized;

using Amazon.S3;
using Amazon.S3.Model;
using Amazon.SecurityToken;
using Amazon.SecurityToken.Model;
using Amazon.Runtime;


using Amazon.IdentityManagement;
using Amazon.IdentityManagement.Model;
using System.Configuration;

namespace AWS_CSharp_Test
{
    class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
         //   FederationTest.Test("Facebook");
         //   FederationTest.Test("Google");
            FederationTest.Test("Amazon");
            
            Console.WriteLine("Press key to exit");
            Console.Read();
        }
    }
}
