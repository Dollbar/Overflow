"""Guard the one-bit active-bank relation added to a complete mapped miter."""
from copy import deepcopy
import unittest
from scripts.add_uart_bank_observation import add_observation


def fixture():
    module={'ports':{},'netnames':{'Storage_Inst.Storage_Inst.read_bank_q':{'bits':[5]},
            'Storage_Inst.Fifo_Inst.reg_pending':{'bits':[7]}},'cells':{
            'bank':{'type':'$dff','port_directions':{'D':'input','Q':'output'},'connections':{'D':[4],'Q':[5]}},
            'pending':{'type':'$dff','port_directions':{'D':'input','Q':'output'},'connections':{'D':[6],'Q':[7]}}}}
    return {'modules':{'gold':deepcopy(module),'gate':deepcopy(module)}}


class UARTBankObservationTests(unittest.TestCase):
    def test_only_adds_observation_and_never_changes_real_logic(self):
        source=fixture(); saved=deepcopy(source);out=add_observation(source)
        self.assertEqual(source,saved)
        for side in ('gold','gate'):
            before=source['modules'][side];after=out['modules'][side]
            for name,value in before['cells'].items():self.assertEqual(after['cells'][name],value)
            observer=after['cells']['uart_active_bank_observer']
            self.assertEqual(observer['type'],'$and')
            self.assertEqual(observer['connections']['A'],[5]);self.assertEqual(observer['connections']['B'],[7])
            self.assertEqual(after['ports']['uart_active_read_bank']['direction'],'output')
            self.assertGreater(observer['connections']['Y'][0],7)

    def test_repeated_instrumentation_rejected(self):
        with self.assertRaises(ValueError):add_observation(add_observation(fixture()))

    def test_missing_or_malformed_state_is_rejected(self):
        for bits in ([],['0'],[True],[5,6]):
            data=fixture();data['modules']['gate']['netnames']['Storage_Inst.Storage_Inst.read_bank_q']['bits']=bits
            with self.subTest(bits=bits),self.assertRaises(ValueError):add_observation(data)

    def test_free_state_cut_and_missing_driver_rejected(self):
        data=fixture();data['modules']['gold']['ports']['bank_cut']={'direction':'input','bits':[5]}
        with self.assertRaises(ValueError):add_observation(data)
        data=fixture();del data['modules']['gate']['cells']['bank']
        with self.assertRaises(ValueError):add_observation(data)

    def test_wrong_module_pair_rejected(self):
        data=fixture();del data['modules']['gate']
        with self.assertRaises(ValueError):add_observation(data)


if __name__=='__main__':unittest.main()
