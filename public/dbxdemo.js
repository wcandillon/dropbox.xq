function selectEntry(e) {
	var targ;
	if (!e) var e = window.event;
	if (e.target) targ = e.target;
	else if (e.srcElement) targ = e.srcElement;
	if (targ.nodeType == 3) // defeat Safari bug
		targ = targ.parentNode;
	
	if (targ.tagName.toLowerCase() == "input" 
		&& targ.type.toLowerCase() == "checkbox") {
		return;
	}
		
	var checkbox = targ.getElementsByTagName("input");
	if (checkbox.length < 1) {
		targ = targ.parentNode;
		checkbox = targ.getElementsByTagName("input");
	}
	if (typeof checkbox[0] != "undefined") {
		if (checkbox[0].checked)
			targ.className = targ.className.replace(" selected ", " ");
		else
			targ.className = targ.className + " selected ";
		checkbox[0].checked = !checkbox[0].checked;
	}
}

function onSearch(query){
	if (query.length < 3) {
		window.alert("Search queries need to be at least 3 characters long!");
		return false;
	} else
		return true;
}