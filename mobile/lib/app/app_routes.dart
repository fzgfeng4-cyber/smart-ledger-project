class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const transactions = '/transactions';
  static const budget = '/budget';
  static const statistics = '/statistics';
  static const newTransaction = '/transaction/new';
  static const editTransaction = '/transaction/edit';
  static const batchConfirm = '/transaction/batch-confirm';
  static const importEntry = '/import';
  static const csvImport = importEntry;
  static const ocr = '/ocr';
  static const aiClassification = '/ai/classification';
}
