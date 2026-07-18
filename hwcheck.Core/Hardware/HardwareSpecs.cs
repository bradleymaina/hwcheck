using System;
using System.Management;

namespace HardwareInfo
{
    public class HardwareInfoRetriever
    {
        
        public string GetHardwareSpecs()
        {
            string serialNumber = "Not Available";

            try
            {
                
                string query = "SELECT SerialNumber FROM Win32_BIOS";
                
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(query))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        if (obj["SerialNumber"] != null)
                        {
                            serialNumber = obj["SerialNumber"].ToString().Trim();
                            break; // Found it, we can stop looping
                        }
                    }
                }
            }
            catch (ManagementException ex)
            {
                Console.WriteLine($"WMI Specific Error: {ex.Message}");
                // Fallback state already handled by initializing to "Not Available"
            }
            catch (Exception ex)
            {
                Console.WriteLine($"General Error accessing WMI: {ex.Message}");
            }

            // Return the value cleanly to whatever UI element called this method
            return serialNumber;
        }
    }
}