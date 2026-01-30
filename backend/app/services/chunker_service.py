"""Text chunking service for RAG pipeline."""
import re
from typing import Optional

from ..config import settings


class ChunkerService:
    """
    Splits transcript text into overlapping chunks for embedding and retrieval.
    
    Preserves timestamp information for each chunk.
    """
    
    def __init__(
        self,
        chunk_size: int = None,
        chunk_overlap: int = None,
    ):
        self.chunk_size = chunk_size or settings.chunk_size
        self.chunk_overlap = chunk_overlap or settings.chunk_overlap
    
    def chunk_segments(
        self,
        segments: list[dict],
    ) -> list[dict]:
        """
        Split transcript segments into chunks for embedding.
        
        Args:
            segments: List of {start, end, text} dicts from ASR
            
        Returns:
            List of chunks with:
                - text: Combined text for the chunk
                - start_time: Start timestamp of first segment in chunk
                - end_time: End timestamp of last segment in chunk
                - segment_indices: Original segment indices included
        """
        if not segments:
            return []
        
        chunks = []
        current_chunk_segments = []
        current_word_count = 0
        
        for i, segment in enumerate(segments):
            segment_text = segment["text"].strip()
            if not segment_text:
                continue
            
            segment_words = self._count_words(segment_text)
            
            # If adding this segment exceeds chunk size, finalize current chunk
            if current_word_count + segment_words > self.chunk_size and current_chunk_segments:
                chunk = self._create_chunk(current_chunk_segments, segments)
                chunks.append(chunk)
                
                # Start new chunk with overlap
                overlap_segments = self._get_overlap_segments(
                    current_chunk_segments,
                    segments
                )
                current_chunk_segments = overlap_segments
                current_word_count = sum(
                    self._count_words(segments[idx]["text"])
                    for idx in [s["index"] for s in overlap_segments]
                ) if overlap_segments else 0
            
            current_chunk_segments.append({
                "index": i,
                "text": segment_text,
                "start": segment["start"],
                "end": segment["end"],
            })
            current_word_count += segment_words
        
        # Don't forget the last chunk
        if current_chunk_segments:
            chunk = self._create_chunk(current_chunk_segments, segments)
            chunks.append(chunk)
        
        return chunks
    
    def _count_words(self, text: str) -> int:
        """Count words in text (works for RU, KZ, EN)."""
        # Split on whitespace and punctuation
        words = re.findall(r'\b\w+\b', text, re.UNICODE)
        return len(words)
    
    def _create_chunk(
        self,
        chunk_segments: list[dict],
        original_segments: list[dict],
    ) -> dict:
        """Create a chunk dict from segments."""
        texts = [seg["text"] for seg in chunk_segments]
        
        return {
            "text": " ".join(texts),
            "start_time": chunk_segments[0]["start"],
            "end_time": chunk_segments[-1]["end"],
            "segment_indices": [seg["index"] for seg in chunk_segments],
        }
    
    def _get_overlap_segments(
        self,
        current_segments: list[dict],
        original_segments: list[dict],
    ) -> list[dict]:
        """Get segments for overlap from the end of current chunk."""
        if not current_segments:
            return []
        
        overlap_segments = []
        overlap_words = 0
        
        # Work backwards through segments
        for seg in reversed(current_segments):
            seg_words = self._count_words(seg["text"])
            if overlap_words + seg_words <= self.chunk_overlap:
                overlap_segments.insert(0, seg)
                overlap_words += seg_words
            else:
                break
        
        return overlap_segments
    
    def chunk_text(
        self,
        text: str,
        preserve_sentences: bool = True,
    ) -> list[str]:
        """
        Simple text chunking without timestamps.
        
        Args:
            text: Plain text to chunk
            preserve_sentences: Try to break at sentence boundaries
            
        Returns:
            List of text chunks
        """
        if not text:
            return []
        
        if preserve_sentences:
            # Split into sentences
            sentences = re.split(r'(?<=[.!?])\s+', text)
        else:
            sentences = [text]
        
        chunks = []
        current_chunk = []
        current_words = 0
        
        for sentence in sentences:
            sentence_words = self._count_words(sentence)
            
            if current_words + sentence_words > self.chunk_size and current_chunk:
                chunks.append(" ".join(current_chunk))
                
                # Overlap: keep last few words worth of content
                overlap_text = " ".join(current_chunk)
                overlap_words = overlap_text.split()[-self.chunk_overlap:]
                current_chunk = [" ".join(overlap_words)] if overlap_words else []
                current_words = len(overlap_words)
            
            current_chunk.append(sentence)
            current_words += sentence_words
        
        if current_chunk:
            chunks.append(" ".join(current_chunk))
        
        return chunks


# Global instance
chunker_service = ChunkerService()
