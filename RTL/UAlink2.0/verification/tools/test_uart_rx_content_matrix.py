"""Check that partial or inconsistent plane evidence cannot claim full-word proof.

Run: python3 -m unittest verification.tools.test_uart_rx_content_matrix -v
Outputs: six matrix acceptance/negative checks. Next: run the actual 32-plane matrix.
"""
import copy
import unittest
from verification.formal.run_uart_rx_content_matrix import planes_complete


def records():
    return [dict(proof_bit=bit,depth=128,content=True,compared_output_bits=93,
                 passed=True,reset_proved=True,induction_proved=True,source_unchanged=True,
                 exit_status=0,source_sha256={'source':'a'},dependency_sha256={'model':'b'})
            for bit in range(32)]


class MatrixAcceptance(unittest.TestCase):
    def test_all_planes_required(self):
        self.assertTrue(planes_complete(records(),128))
        self.assertFalse(planes_complete(records()[:-1],128))
        self.assertFalse(planes_complete(records()+records()[:1],128))

    def test_duplicate_and_boolean_plane_rejected(self):
        for bit in (0,True,32,-1):
            cases=records();cases[1]['proof_bit']=bit
            self.assertFalse(planes_complete(cases,128))

    def test_any_failed_gate_rejected(self):
        for key in ('passed','reset_proved','induction_proved','source_unchanged','content'):
            cases=records();cases[31][key]=False
            self.assertFalse(planes_complete(cases,128))
        cases=records();cases[0]['exit_status']=124
        self.assertFalse(planes_complete(cases,128))

    def test_scope_mismatch_rejected(self):
        for key,value in (('depth',129),('depth',True),('compared_output_bits',124)):
            cases=records();cases[17][key]=value
            self.assertFalse(planes_complete(cases,128))

    def test_mixed_source_or_model_rejected(self):
        for key in ('source_sha256','dependency_sha256'):
            cases=records();cases[9][key]={'different':'c'}
            self.assertFalse(planes_complete(cases,128))
            cases[9][key]={}
            self.assertFalse(planes_complete(cases,128))

    def test_missing_fields_and_nonrecord_rejected(self):
        for key in records()[0]:
            cases=records();del cases[0][key]
            self.assertFalse(planes_complete(cases,128))
        cases=records();cases[0]=None
        self.assertFalse(planes_complete(cases,128))


if __name__=='__main__':unittest.main()
