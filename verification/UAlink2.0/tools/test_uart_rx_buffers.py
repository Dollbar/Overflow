"""RX top must receive actual macro-connected repair without changing other sinks."""
from copy import deepcopy
import unittest
from scripts.buffer_storage import buffer_storage
from verification.tools.test_storage_buffers import fixture

class UARTRxBufferTests(unittest.TestCase):
    def test_rx_supported_preserving_observers_clocks_and_constants(self):
        design=fixture();design['modules']['dl_uart_rx_path']=design['modules'].pop('upli_receive_storage')
        before=deepcopy(design);result=buffer_storage(design,top='dl_uart_rx_path')
        self.assertEqual(design,before)
        old=before['modules']['dl_uart_rx_path'];new=result['modules']['dl_uart_rx_path']
        self.assertEqual(set(result['modules']),{'dl_uart_rx_path'})
        self.assertEqual(new['cells']['observer'],old['cells']['observer'])
        macro=new['cells']['memory']['connections']
        for port,stages in (('D',3),('WA',3),('RA',3),('WCS',1),('RCS',1)):
            bit=macro[port][0]
            for _ in range(stages):
                drivers=[c for n,c in new['cells'].items() if n.startswith('storage_hold_') and c['connections']['Z']==[bit]]
                self.assertEqual(len(drivers),1);self.assertEqual(drivers[0]['type'],'BUFFD0BWP40P140')
                bit=drivers[0]['connections']['I'][0]
            self.assertEqual(bit,old['cells']['memory']['connections'][port][0])
            self.assertEqual(macro[port][1:],old['cells']['memory']['connections'][port][1:])
        for port in ('WCLK','RCLK','Q','WM'):
            self.assertEqual(macro[port],old['cells']['memory']['connections'][port])
        with self.assertRaises(ValueError):buffer_storage(result,top='dl_uart_rx_path')

if __name__=='__main__':unittest.main()
