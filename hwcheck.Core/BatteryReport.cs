using System;
using Windows.Devices.Power;

namespace Battery
{
    public class BatteryInfo
    {
        public void GetBatteryHealth()
        {
            var report = global::Windows.Devices.Power.Battery.AggregateBattery.GetReport();

            var designCapacity = report.DesignCapacityInMilliwattHours ?? 0;
            var fullChargeCapacity = report.FullChargeCapacityInMilliwattHours ?? 0;

            if (fullChargeCapacity == 0)
            {
                Console.WriteLine("Cannot determine battery health because full charge capacity is unknown or zero.");
                return;
            }

            var batteryHealth = (double)fullChargeCapacity / designCapacity * 100;
            Console.WriteLine($"Battery Health: {batteryHealth:F2}%");

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
    }

    public static class Program
    {
        public static void Main()
        {
            var batteryInfo = new BatteryInfo();
            batteryInfo.GetBatteryHealth();
        }
    }
}
