$(document).ready(function () {	
	
	$('#show_other_classifications').bind('ajax:beforeSend', function() {		
  		$('.loader_image').show();
	});

	$('#show_other_classifications').bind('ajax:complete', function() {
  		$('.loader_image').hide();
	});	
});