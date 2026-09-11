"""Run: python3 verification/tl_prepared_partition/test_mapped_state.py.
Checks the real-equation observation contract with a small complete FF graph and
deliberate corruptions. No EDA installation needed. Next run actual mapped proof.
"""
import copy
import importlib.util
import unittest


def fixture():
    def cell(kind,connections,directions):
        return dict(type=kind,connections=connections,port_directions=directions,parameters={})
    graph=dict(ports=dict(i_clk=dict(direction='input',bits=[2]),i_data=dict(direction='input',bits=[3]),o_data=dict(direction='output',bits=[5])),
               netnames=dict(owner=dict(bits=[4]),payload=dict(bits=[5]),alias=dict(bits=[5,'0',5])),
               cells=dict(owner_ff=cell('$_DFF_P_',dict(C=[2],D=[3],Q=[4]),dict(C='input',D='input',Q='output')),
                          payload_ff=cell('$_DFF_P_',dict(C=[2],D=[6],Q=[5]),dict(C='input',D='input',Q='output')),
                          update=cell('$_XOR_',dict(A=[3],B=[4],Y=[6]),dict(A='input',B='input',Y='output'))))
    return graph,['owner','payload','alias']


class Tests(unittest.TestCase):
    def output_parser(self):
        import check_mapped
        parse=getattr(check_mapped,'binary_outputs',None)
        self.assertIsNotNone(parse,'trace audit must compare all 531 bits numerically')
        return parse

    def test_hex_padding_does_not_change_output_value(self):
        parse=self.output_parser()
        self.assertEqual(parse(['0'*133,'0'*132+'1']),parse(['0','1']))

    def test_unknown_output_is_rejected(self):
        parse=self.output_parser()
        with self.assertRaises(ValueError):parse(['00x1'])

    def test_extra_output_bit_cannot_be_truncated(self):
        parse=self.output_parser()
        with self.assertRaises(ValueError):parse([format(1<<531,'x')])

    def counterexample_checker(self):
        import check_mapped
        check=getattr(check_mapped,'sat_counterexample',None)
        self.assertIsNotNone(check,'SAT audit must inspect the actual failing output witness')
        return check

    def test_short_actual_counterexample_does_not_require_buffered_banner(self):
        check=self.counterexample_checker()
        self.assertTrue(check(dict(exit=1),'ERROR: Called with -verify and proof did fail!',dict(signal=[dict(name='o_bad',wave='14')])) )

    def test_parser_error_with_stale_witness_is_not_a_counterexample(self):
        check=self.counterexample_checker()
        self.assertFalse(check(dict(exit=1),'ERROR: syntax error',dict(signal=[dict(name='o_bad',wave='14')])) )

    def test_zero_bad_output_is_not_a_counterexample(self):
        check=self.counterexample_checker()
        self.assertFalse(check(dict(exit=1),'ERROR: Called with -verify and proof did fail!',dict(signal=[dict(name='o_bad',wave='04')])) )

    def test_timeout_with_stale_witness_is_not_a_counterexample(self):
        check=self.counterexample_checker()
        self.assertFalse(check(dict(exit=124),'ERROR: Called with -verify and proof did fail!',dict(signal=[dict(name='o_bad',wave='14')])) )

    def test_bad_output_alias_resolves_to_exact_graph_bit(self):
        check=self.counterexample_checker()
        graph=dict(ports=dict(o_bad=dict(bits=[4]),i_source_valid=dict(bits=[4])))
        self.assertTrue(check(dict(exit=1),'ERROR: Called with -verify and proof did fail!',dict(signal=[dict(name='i_source_valid',wave='14')]),graph))

    def test_unrelated_high_input_cannot_replace_bad_output(self):
        check=self.counterexample_checker()
        graph=dict(ports=dict(o_bad=dict(bits=[4]),i_source_valid=dict(bits=[5])))
        self.assertFalse(check(dict(exit=1),'ERROR: Called with -verify and proof did fail!',dict(signal=[dict(name='i_source_valid',wave='14')]),graph))

    def test_nonzero_verilog_range_keeps_actual_blif_pin_names(self):
        import run_mapped_cec
        names=getattr(run_mapped_cec,'port_names',None)
        self.assertIsNotNone(names,'BLIF pin inventory must preserve declared bit offset')
        self.assertEqual(names('r_starts',dict(bits=[10,11,12,13,14,15,16],offset=1)),
                         ['r_starts[1]','r_starts[2]','r_starts[3]','r_starts[4]','r_starts[5]','r_starts[6]','r_starts[7]'])

    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('mapped_state'),'complete mapped-state observer must exist')
        from mapped_state import observe
        self.observe=observe

    def auditor(self):
        import mapped_state
        audit=getattr(mapped_state,'audit_cut',None)
        self.assertIsNotNone(audit,'independent actual D/Q cut audit must exist')
        return audit

    def test_audit_rejects_next_state_replaced_with_current_q(self):
        audit=self.auditor();graph,fields=fixture();cut,layout=self.observe(graph,fields)
        audit(graph,cut,layout)
        cut['ports']['n_state']['bits'][1]=5
        with self.assertRaises(ValueError):audit(graph,cut,layout)

    def test_audit_rejects_state_alias_replaced_with_constant(self):
        audit=self.auditor();graph,fields=fixture();cut,layout=self.observe(graph,fields)
        layout['aliases']['payload']=['0']
        with self.assertRaises(ValueError):audit(graph,cut,layout)

    def test_audit_rejects_original_output_omission(self):
        audit=self.auditor();graph,fields=fixture();cut,layout=self.observe(graph,fields)
        del cut['ports']['o_data']
        with self.assertRaises(ValueError):audit(graph,cut,layout)

    def test_all_real_q_and_d_are_exposed_with_aliases_and_constants(self):
        graph,fields=fixture();cut,layout=self.observe(graph,fields)
        self.assertEqual(cut['ports']['s_state'],dict(direction='input',bits=[4,5]))
        self.assertEqual(cut['ports']['n_state'],dict(direction='output',bits=[3,6]))
        self.assertEqual(layout['aliases'],dict(owner=[0],payload=[1],alias=[1,'0',1]))
        self.assertEqual(cut['cells'],dict(update=graph['cells']['update']))
        self.assertEqual(cut['netnames'],graph['netnames'])
        self.assertEqual({n:cut['ports'][n] for n in graph['ports']},graph['ports'])

    def test_unobserved_real_ff_is_rejected(self):
        graph,fields=fixture()
        with self.assertRaises(ValueError):self.observe(graph,['owner'])

    def test_wrong_real_clock_is_rejected(self):
        graph,fields=fixture();graph['cells']['payload_ff']['connections']['C']=[3]
        with self.assertRaises(ValueError):self.observe(graph,fields)

    def test_unknown_sequential_primitive_is_rejected(self):
        graph,fields=fixture();graph['cells']['payload_ff']['type']='$_DFF_N_'
        with self.assertRaises(ValueError):self.observe(graph,fields)

    def test_undriven_next_state_is_rejected(self):
        graph,fields=fixture();graph['cells']['payload_ff']['connections']['D']=[999]
        with self.assertRaises(ValueError):self.observe(graph,fields)

    def test_a_combinational_node_cannot_impersonate_state(self):
        graph,fields=fixture();graph['netnames']['payload']['bits']=[6]
        with self.assertRaises(ValueError):self.observe(graph,fields)

    def test_duplicate_state_driver_is_rejected(self):
        graph,fields=fixture();graph['cells']['duplicate']=copy.deepcopy(graph['cells']['payload_ff'])
        with self.assertRaises(ValueError):self.observe(graph,fields)


if __name__=='__main__':unittest.main()
