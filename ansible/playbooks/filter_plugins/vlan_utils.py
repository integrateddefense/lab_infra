def to_cisco_range(vlan_list):
	if not vlan_list:
		return ""
	v_ids = sorted(list(set(int(v) for v in vlan_list)))

	ranges = []
	if not v_ids:
		return ""

	start = end = v_ids[0]

	for v in v_ids[1:]:
		if v == end+1:
			end = v
		else:
			ranges.append(f"{start}-{end}" if start != end else f"{start}")
			start = end = v
	ranges.append(f"{start}-{end}" if start != end else f"{start}")

	return ",".join(ranges)

class FilterModule(object):
	def filters(self):
		return {
			'to_cisco_range': to_cisco_range
		}
