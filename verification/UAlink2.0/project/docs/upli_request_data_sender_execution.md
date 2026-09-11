# Typed native Request/OrigData shared sender

The full goal still includes all four native UPLI channels, receive storage/return credits, connection/reset, RAS and endpoint transaction integration. This increment builds the real transmit side for Request and OrigData around the existing single upli_burst_sender. It does not replace the full station shell with a misleading completed claim.

The shared helper owns exactly one burst_sender and therefore one pair of Request/OrigData credit banks, one shared TDM phase, and one complete-staged tail ownership path. Typed output modules only preserve all native fields and generate parity protection groups; they must not independently reserve or consume credits. Source candidate acceptance remains the existing actual request send event.

The local184-bit request bundle is {ASI2, AuthTag64, Src10, Dst10, Tag11, NumBeats2, Address57, Command6, Length6, Attr8, Metadata8}. Actual Port2/VC2/Pool1 come from the shared sender event. All2048 data bits,256 byte enables and4 Error bits are staged per candidate. The input producer must supply a legal command and matching has_data/NumBeats geometry, and zero authorization tags when authorization is inactive. This transport does not reinterpret unsupported commands as ordinary memory requests.

Keep the existing sender parameters other than request width (fixed184 here), same candidate/credit/init interfaces and status outputs. Expose complete typed Request fields plus Request parity and complete OrigData fields plus parity. There is no new ready on native outputs. Both channels use the existing sender reset and connection qualification, including the requirement that connection qualification remain stable until reset.

TDD: demonstrate absent wrapper interface, then test actual shared wrapper with independent staged-burst model and literal field/parity checks; parameters1/2/4 ports, credit widths and initialization, first-beat coincidence, continuousper-port tails/TDM, Read overlay, candidate noise, no-credit suppression and reset. Inject real metadata/port/parity/data wiring faults. New RTL candidates remain isolated until current Read reset evidence freezes.

Expected deliverables: rtl/upli/upli_request_data_sender.v, typed channel/parity RTL, verification/upli_channels self-checks and bounded reviews, inventory update and authorized relocated publication. Evidence does not close native Read/Write response channels, receiver isolation, standard station integration, CDC/RDC or STA.
