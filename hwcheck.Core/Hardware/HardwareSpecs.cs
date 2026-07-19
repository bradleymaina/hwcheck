using System;
using System.Management;

namespace HardwareInfo
{
    public class HardwareInfoRetriever
    {
        public string GetSerialNumber()
        {
            string serial_number = "Not Available";

            try
            {
                string query = "SELECT SerialNumber FROM Win32_BIOS";

                using (ManagementObjectSearcher search_sn = new ManagementObjectSearcher(query))
                {
                    foreach (ManagementObject obj in search_sn.Get())
                    {
                        if (obj["SerialNumber"] != null)
                        {
                            serial_number = obj["SerialNumber"].ToString().Trim();
                            break;
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

            return serial_number;
        }

        public string GetLaptopModel()
        {
            string laptop_model = "Not Available";

            try
            {
                string query = "SELECT Model FROM Win32_ComputerSystem";

                using (ManagementObjectSearcher searcher_lm = new ManagementObjectSearcher(query))
                {
                    foreach (ManagementObject obj in searcher_lm.Get())
                    {
                        if (obj["Model"] != null)
                        {
                            laptop_model = obj["Model"].ToString().Trim();
                            break;
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

            return laptop_model;
        }
    }
}