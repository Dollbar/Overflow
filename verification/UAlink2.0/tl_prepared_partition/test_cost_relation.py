"""Run: python3 verification/tl_prepared_partition/test_cost_relation.py.
Synthetic checks for the context-substitution gate: escaping changes, hidden
state, temporary collisions and account-dependent arithmetic must be rejected.
No EDA artifacts are created; next run the actual-block SAT and state CEC.
"""
import unittest
from check_cost_relation import replacement


class CostContextTests(unittest.TestCase):
    def setUp(self):
        self.declaration='wire [5:0] contribution[0:7];wire [5:0] pair[0:3];wire [5:0] quad[0:1];'
        self.old=self.declaration+'\n assign pair[0]=contribution[0]+contribution[1];\nend endgenerate // 结束复用费用\nassign taken=valid&&ready;\n'
        self.block='// BEGIN_COST_COMPRESSION\n wire [5:0] cost_sum_0,cost_carry_0;\n assign cost_sum_0=contribution[0]^contribution[1];\n assign cost_carry_0=(contribution[0]&contribution[1])<<1;\n assign prefix_cost[(account*8+1)*6+:6]=cost_sum_0+cost_carry_0;\n// END_COST_COMPRESSION\n'
        self.new='wire [5:0] contribution[0:7];\n'+self.block+'end endgenerate // 结束复用费用\nassign taken=valid&&ready;\n'

    def test_exact_local_context(self):
        replacement(self.old,self.new)

    def test_output_change_rejected(self):
        with self.assertRaisesRegex(ValueError,'change outside'):
            replacement(self.old,self.new.replace('valid&&ready','valid'))

    def test_hidden_state_rejected(self):
        with self.assertRaisesRegex(ValueError,'pure local'):
            replacement(self.old,self.new.replace(' wire [5:0]',' reg [5:0]'))

    def test_account_specific_expression_rejected(self):
        with self.assertRaisesRegex(ValueError,'only on local contribution'):
            replacement(self.old,self.new.replace('=cost_sum_0+cost_carry_0','=cost_sum_0+account'))

    def test_oracle_signal_dependency_rejected(self):
        with self.assertRaisesRegex(ValueError,'only on local contribution'):
            replacement(self.old,self.new.replace('=cost_sum_0+cost_carry_0','=values[11:6]'))

    def test_escaped_temporary_rejected(self):
        suffix='assign escaped=cost_sum_0;\n'
        with self.assertRaisesRegex(ValueError,'temporary escapes'):
            replacement(self.old+suffix,self.new+suffix)


if __name__=='__main__':unittest.main()
