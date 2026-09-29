// dart run forui style create date-field



class FormDateFieldExample extends StatefulWidget {
  @override
  State<FormDateFieldExample> createState() => _FormDateFieldExampleState();
}

class _FormDateFieldExampleState extends State<FormDateFieldExample> {
  final _key = GlobalKey<FormState>();
  late final _startSelection = FDateSelectionController.single();

  @override
  void dispose() {
    _startSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext _) => Form(
    key: _key,
    child: Column(
      spacing: 16,
      children: [
        FDateField(
          validator: (date) => switch (date) {
            null => 'Please select a start date',
            final date when date.isBefore(.now()) =>
              'Start date must be in the future',
            _ => null,
          },
          selectionControl: .managedSingle(controller: _startSelection),
          label: const Text('Start Date'),
          description: const Text('Select a start date'),
          autovalidateMode: .disabled,
        ),
        const SizedBox(height: 20),
        FDateField(
          validator: (date) => switch (date) {
            null => 'Please select an end date',
            final date
                when _startSelection.value != null &&
                    date.isBefore(_startSelection.value!) =>
              'Start date must be in the future',
            _ => null,
          },
          label: const Text('End Date'),
          description: const Text('Select an end date'),
          autovalidateMode: .disabled,
        ),
        Row(
          mainAxisAlignment: .end,
          children: [
            FButton(
              size: .sm,
              mainAxisSize: .min,
              child: const Text('Submit'),
              onPress: () {
                if (_key.currentState!.validate()) {
                  // Form is valid, do something.
                }
              },
            ),
          ],
        ),
      ],
    ),
  );
}
