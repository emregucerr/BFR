$(function() {
  $('.data input').change(function() {
    $(this).closest('form').submit();
  });
});
