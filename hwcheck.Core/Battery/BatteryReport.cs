using System;
using Windows.Devices.Power;
using System.Management;
using HardwareInfo;

namespace Battery
{
    public class BatteryInfo
    {
        public void GetBatteryHealth()
        {
            var report = global::Windows.Devices.Power.Battery.AggregateBattery.GetReport();

            var designCapacity = report.DesignCapacityInMilliwattHours ?? 0;
            var fullChargeCapacity = report.FullChargeCapacityInMilliwattHours ?? 0;

            if (designCapacity == 0 || fullChargeCapacity == 0)
            {
                Console.WriteLine("Cannot determine battery health because design capacity or full charge capacity is unknown or zero.");
                return;
            }

            var batteryHealth = (double)fullChargeCapacity / designCapacity * 100;
            Console.WriteLine($"Battery Health: {batteryHealth:F2}%");

            //var batteryWear = 100 - batteryHealth;
            //Console.WriteLine($"Battery Wear: {batteryWear:F2}%");

            if (batteryHealth > 80)
            {
                Console.WriteLine("Battery health is Excellent.");
            }else if(batteryHealth > 70)
            {
                Console.WriteLine("Battery health is Good.");
            }else if(batteryHealth < 70)
            {
                Console.WriteLine("Warning: Battery health is Poor.");
            }
        }
        /// <summary>
        /// Retrieves the battery Cycle Count using WMI (Windows Management Instrumentation).
        /// Returns nill if the cycle count is not  supported or cannot be retrieved.
        /// </summary>
        public int? GetBatteryCycleCount()
        {
            try
            {
                var scope = new ManagementScope(@"\\.\root\wmi");
                scope.Connect();

                var query = new ObjectQuery("SELECT CycleCount FROM BatteryCycleCount");

                using var searcher = new ManagementObjectSearcher(scope, query);
                foreach (ManagementObject obj in searcher.Get())
                {
                    if (obj["CycleCount"] is int cycleCount)
                    {
                        return cycleCount;
                    }

                    if (obj["CycleCount"] is uint uintCycleCount)
                    {
                        return (int)uintCycleCount;
                    }

                    if (obj["CycleCount"] is string stringCycleCount && int.TryParse(stringCycleCount, out var parsedCycleCount))
                    {
                        return parsedCycleCount;
                    }
                }
            }
            catch (ManagementException)
            {
                return null;
            }
            catch (Exception)
            {
                return null;
            }

            return null;
        }
    }
    public static class Program
    {
        public static void Main()
        {

            //instantiate the class
            HardwareInfoRetriever retriever = new HardwareInfoRetriever();

            //call the method
            string serialNumber = retriever.GetSerialNumber();
            string LaptopModel = retriever.GetLaptopModel();

            Console.WriteLine("---------------------------------");
            Console.WriteLine("\tSystem Specifications\t");
            Console.WriteLine("---------------------------------");
            Console.WriteLine($"Laptop Model: {LaptopModel}");
            Console.WriteLine($"Serial Number: {serialNumber}");
            Console.WriteLine("\n");
            Console.WriteLine("---------------------------------");
            Console.WriteLine("\tBattery Information\t");
            Console.WriteLine("---------------------------------");

            var batteryInfo = new BatteryInfo();
            batteryInfo.GetBatteryHealth();

            var cycleCount = batteryInfo.GetBatteryCycleCount();
            Console.WriteLine(cycleCount is null
                ? "Battery cycle count is not available on this device."
                : $"Battery cycle count: {cycleCount}");
            if (cycleCount == 0)
            {
                Console.WriteLine("Your hardware does not expose the battery cycle count. This is common on some devices, especially laptops that do not provide this information through WMI.");
            }else if (cycleCount > 1000)
            {
                Console.WriteLine("Warning: Your battery cycle count is unusually high. This may indicate that your battery has been heavily used and may be nearing the end of its lifespan.");
            }else
            {
                Console.WriteLine("Your battery cycle count is within a normal range.");
            }
            
            
        }
    }
}
