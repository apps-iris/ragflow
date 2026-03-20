import { useSelectedIds } from '@/hooks/logic-hooks/use-row-selection';
import { useDownloadFile } from '@/hooks/use-file-request';
import { IFile } from '@/interfaces/database/file-manager';
import { OnChangeFn, RowSelectionState } from '@tanstack/react-table';
import { Download, FolderInput, Trash2 } from 'lucide-react';
import { useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useHandleDeleteFile } from './use-delete-file';
import { UseMoveDocumentShowType } from './use-move-file';

export function useBulkOperateFile({
  files,
  rowSelection,
  showMoveFileModal,
  setRowSelection,
}: {
  files: IFile[];
  rowSelection: RowSelectionState;
  setRowSelection: OnChangeFn<RowSelectionState>;
} & UseMoveDocumentShowType) {
  const { t } = useTranslation();

  const { selectedIds } = useSelectedIds(rowSelection, files);

  const { handleRemoveFile } = useHandleDeleteFile();
  const { downloadFile } = useDownloadFile();

  const handleDownload = useCallback(async () => {
    const selectedFiles = files.filter((f) => selectedIds.includes(f.id));
    for (const file of selectedFiles) {
      await downloadFile({ id: file.id, filename: file.name });
    }
  }, [files, selectedIds, downloadFile]);

  const list = [
    {
      id: 'download',
      label: t('common.download'),
      icon: <Download />,
      onClick: handleDownload,
    },
    {
      id: 'move',
      label: t('common.move'),
      icon: <FolderInput />,
      onClick: () => {
        showMoveFileModal(selectedIds, true);
      },
    },
    {
      id: 'delete',
      label: t('common.delete'),
      icon: <Trash2 />,
      onClick: async () => {
        const code = await handleRemoveFile(selectedIds);
        if (code === 0) {
          setRowSelection({});
        }
      },
    },
  ];

  return { list };
}
